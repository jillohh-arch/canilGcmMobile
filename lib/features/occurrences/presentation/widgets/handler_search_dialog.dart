import 'package:flutter/material.dart';
import 'package:canil_gcm/core/services/user_service.dart';

class HandlerSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> currentTeam;
  final Function(Map<String, dynamic>) onSelected;

  const HandlerSearchDialog({
    super.key,
    required this.currentTeam,
    required this.onSelected,
  });

  @override
  State<HandlerSearchDialog> createState() => _HandlerSearchDialogState();
}

class _HandlerSearchDialogState extends State<HandlerSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final UserService _userService = UserService();
  Stream<List<Map<String, dynamic>>>? _handlersStream;
  final List<Map<String, dynamic>> _selectedHandlers = [];

  @override
  void initState() {
    super.initState();
    _handlersStream = _userService.getAllHandlers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _handlersStream = _userService.searchHandlers(value);
    });
  }

  bool _isHandlerSelected(String ra) {
    return _selectedHandlers.any((h) => h['ra'] == ra);
  }

  bool _isHandlerInTeam(String ra) {
    return widget.currentTeam.any((member) => member['handler_id'] == ra);
  }

  void _toggleHandlerSelection(Map<String, dynamic> handler) {
    setState(() {
      if (_isHandlerSelected(handler['ra'])) {
        _selectedHandlers.removeWhere((h) => h['ra'] == handler['ra']);
      } else {
        _selectedHandlers.add(handler);
      }
    });
  }

  void _confirmSelection() {
    if (_selectedHandlers.isNotEmpty) {
      widget.onSelected(_selectedHandlers.first);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adicionar Integrante',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecione um condutor para adicionar à equipe',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar por nome ou RA...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),

            const SizedBox(height: 16),

            // Results list
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _handlersStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text('Nenhum condutor encontrado'),
                    );
                  }

                  final handlers = snapshot.data!;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: handlers.length,
                    itemBuilder: (context, index) {
                      final handler = handlers[index];
                      final isSelected = _isHandlerSelected(handler['ra']);
                      final isInTeam = _isHandlerInTeam(handler['ra']);
                      final isDisabled = isInTeam && !isSelected;
                      final imageUrl = handler['imageUrl']?.toString().trim();
                      final displayName = handler['name']?.toString().trim();
                      final fallbackLabel = displayName?.isNotEmpty == true
                          ? displayName!
                          : handler['callsign']?.toString().trim().isNotEmpty ==
                                true
                          ? handler['callsign'].toString().trim()
                          : handler['ra'].toString();
                      final initial = fallbackLabel.characters.first
                          .toUpperCase();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: isDisabled
                              ? null
                              : () => _toggleHandlerSelection(handler),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDisabled
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest
                                  : isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  backgroundImage: imageUrl?.isNotEmpty == true
                                      ? NetworkImage(imageUrl!)
                                      : null,
                                  child: imageUrl?.isNotEmpty != true
                                      ? Text(
                                          initial,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),

                                // Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fallbackLabel,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text(
                                        'RA: ${handler['ra']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Status
                                if (isInTeam)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedHandlers.isNotEmpty
                        ? _confirmSelection
                        : null,
                    child: const Text('Adicionar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
