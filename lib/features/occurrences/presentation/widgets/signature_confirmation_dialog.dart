import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_team_view_model.dart';

class SignatureConfirmationDialog extends StatefulWidget {
  final Occurrence occurrence;
  final OccurrenceTeamViewModel viewModel;
  final VoidCallback onSuccess;

  const SignatureConfirmationDialog({
    super.key,
    required this.occurrence,
    required this.viewModel,
    required this.onSuccess,
  });

  @override
  State<SignatureConfirmationDialog> createState() =>
      _SignatureConfirmationDialogState();
}

class _SignatureConfirmationDialogState
    extends State<SignatureConfirmationDialog> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final TextEditingController _passwordController = TextEditingController();

  bool _isBiometricAvailable = false;
  bool _isBiometricAuthenticating = false;
  bool _isPasswordAuthenticating = false;
  String? _errorMessage;
  String? _signatureHash;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final available =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!mounted) return;
      setState(() => _isBiometricAvailable = available);
    } catch (error) {
      debugPrint('Erro ao verificar biometria: $error');
    }
  }

  Future<void> _handleBiometricSignature() async {
    final signerError = _signatureGuardMessage(_currentHandlerRaOrNull());
    if (signerError != null) {
      setState(() => _errorMessage = signerError);
      return;
    }

    setState(() {
      _isBiometricAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Confirme sua identidade para assinar a ocorrência',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        await _completeSignature(SignatureMethod.biometric);
      } else if (mounted) {
        setState(() => _errorMessage = 'Autenticação biométrica recusada');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Erro ao autenticar: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isBiometricAuthenticating = false);
      }
    }
  }

  Future<void> _handlePasswordSignature() async {
    final handlerRa = _currentHandlerRaOrNull();
    final signerError = _signatureGuardMessage(handlerRa);
    if (signerError != null) {
      setState(() => _errorMessage = signerError);
      return;
    }

    setState(() {
      _isPasswordAuthenticating = true;
      _errorMessage = null;
    });

    try {
      if (_passwordController.text.isEmpty) {
        setState(() => _errorMessage = 'Digite sua senha');
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null || handlerRa == null) {
        setState(
          () => _errorMessage =
              'Não foi possível identificar o usuário autenticado',
        );
        return;
      }

      final email = user.email?.trim().isNotEmpty == true
          ? user.email!.trim()
          : HandlerIdentityService.emailFromRa(handlerRa);
      final credential = EmailAuthProvider.credential(
        email: email,
        password: _passwordController.text,
      );

      await user.reauthenticateWithCredential(credential);
      await _completeSignature(SignatureMethod.password);
    } on FirebaseAuthException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('wrong-password') ||
          code.contains('invalid-credential') ||
          code.contains('user-mismatch')) {
        setState(() => _errorMessage = 'Senha não confere com o usuário atual');
      } else {
        setState(
          () => _errorMessage =
              'Não foi possível confirmar a senha: ${error.message ?? error.code}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Erro ao autenticar: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isPasswordAuthenticating = false);
      }
    }
  }

  Future<void> _completeSignature(SignatureMethod method) async {
    final handlerId = _currentHandlerRaOrNull();
    final signerError = _signatureGuardMessage(handlerId);
    if (signerError != null || handlerId == null) {
      setState(
        () => _errorMessage =
            signerError ?? 'Não foi possível identificar o usuário autenticado',
      );
      return;
    }

    final now = DateTime.now().toUtc();
    final occurrenceHashPreview = _occurrenceHashPreview();
    final dataToHash =
        '$occurrenceHashPreview|$handlerId|${now.toIso8601String()}|${method.toMap()}';
    final hash = sha256.convert(utf8.encode(dataToHash)).toString();

    setState(() => _signatureHash = hash);

    final signature = OccurrenceSignature(
      handlerId: handlerId,
      status: SignatureStatus.signed,
      signedAt: now,
      signatureMethod: method,
      signatureHash: hash,
    );

    await widget.viewModel.addSignature(
      signature: signature,
      onSuccess: (message) {
        if (!mounted) return;
        _showSuccess(message);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _errorMessage = error);
      },
    );
  }

  void _showSuccess(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green),
        title: const Text('Assinatura realizada'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) Navigator.of(this.context).pop();
              widget.onSuccess();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String? _currentHandlerRaOrNull() {
    return HandlerIdentityService.raFromUser(FirebaseAuth.instance.currentUser);
  }

  OccurrenceTeamMember? _teamMemberFor(String handlerRa) {
    for (final member in widget.occurrence.team) {
      if (member.handlerId == handlerRa) return member;
    }
    return null;
  }

  bool _hasSigned(String handlerRa) {
    return widget.viewModel.signatures.any(
      (signature) =>
          signature.handlerId == handlerRa &&
          signature.status == SignatureStatus.signed,
    );
  }

  String? _signatureGuardMessage(String? handlerRa) {
    if (widget.occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return 'A ocorrência não está aguardando assinaturas';
    }
    if (handlerRa == null || handlerRa.isEmpty) {
      return 'Não foi possível identificar o usuário autenticado';
    }

    final member = _teamMemberFor(handlerRa);
    if (member == null) {
      return 'Somente integrantes da equipe podem assinar esta ocorrência';
    }
    if (member.role == TeamRole.titular) {
      return 'O titular fecha a ocorrência, mas não assina como integrante';
    }
    if (_hasSigned(handlerRa)) {
      return 'Esta ocorrência já foi assinada por este usuário';
    }
    return null;
  }

  String _occurrenceHashPreview() {
    final storedHash = widget.occurrence.integrityHash?.trim();
    if (storedHash != null && storedHash.isNotEmpty) return storedHash;

    final orderedTeam = List<OccurrenceTeamMember>.from(widget.occurrence.team)
      ..sort((a, b) => a.handlerId.compareTo(b.handlerId));
    final payload = <String, dynamic>{
      'hash_version': 3,
      'occurrence_id': widget.occurrence.id,
      'primary_handler_id': widget.occurrence.primaryHandlerId,
      'primary_handler_ra': widget.occurrence.primaryHandlerRa,
      'signature_deadline': widget.occurrence.signatureDeadline
          ?.toUtc()
          .toIso8601String(),
      'signature_request_at': widget.occurrence.signatureRequestAt
          ?.toUtc()
          .toIso8601String(),
      'status': widget.occurrence.status.toMap(),
      'team': orderedTeam.map((member) => member.toHashPayload()).toList(),
    };
    return sha256.convert(utf8.encode(_canonicalJson(payload))).toString();
  }

  String _canonicalJson(dynamic value) {
    return jsonEncode(_normalizeForHash(value));
  }

  dynamic _normalizeForHash(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()
        ..sort();
      return {for (final key in sortedKeys) key: _normalizeForHash(value[key])};
    }
    if (value is Iterable) {
      return value.map(_normalizeForHash).toList();
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final handlerRa = _currentHandlerRaOrNull();
    final signerError = _signatureGuardMessage(handlerRa);
    final isSubmitting =
        _isBiometricAuthenticating || _isPasswordAuthenticating;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.draw_rounded,
                    color: Colors.black87,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confirmar Assinatura',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'RA: ${handlerRa ?? 'não identificado'}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(
                      icon: Icons.event,
                      title: 'Ocorrência',
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.occurrence.typeName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Protocolo: ${widget.occurrence.id.substring(0, 8)}...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Data: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.occurrence.startedAt)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      icon: Icons.groups,
                      title: 'Equipe',
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final member in widget.occurrence.team)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    member.role == TeamRole.titular
                                        ? Icons.workspace_premium_rounded
                                        : Icons.person,
                                    size: 16,
                                    color: member.role == TeamRole.titular
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${member.role == TeamRole.titular ? 'Titular' : 'Integrante'}: ${member.handlerId}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      icon: Icons.list_alt,
                      title: 'Ações registradas',
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.occurrence.results.length} resultado(s)',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            '${widget.occurrence.finalizationPhotos.length} foto(s) de finalização',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ao assinar, você confirma que revisou o conteúdo e está de acordo com o registro.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_signatureHash != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Hash: ${_signatureHash!.substring(0, 16)}...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (signerError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  signerError,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              enabled: signerError == null && !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: signerError == null && !isSubmitting
                  ? (_) => _handlePasswordSignature()
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                if (_isBiometricAvailable)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton.tonalIcon(
                        onPressed: signerError != null || isSubmitting
                            ? null
                            : _handleBiometricSignature,
                        icon: _isBiometricAuthenticating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.fingerprint),
                        label: Text(
                          _isBiometricAuthenticating
                              ? 'Autenticando...'
                              : 'Biometria',
                        ),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: signerError != null || isSubmitting
                      ? null
                      : _handlePasswordSignature,
                  child: _isPasswordAuthenticating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirmar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }
}
