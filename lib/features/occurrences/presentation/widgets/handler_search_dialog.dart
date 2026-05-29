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

  bool _isHandlerInTeam(String ra) {
    return widget.currentTeam.any((member) => member['handler_id'] == ra);
  }

  void _addHandler(Map<String, dynamic> handler) {
    widget.onSelected(handler);
    Navigator.pop(context);
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
                    'Toque no + ao lado do condutor para adicionar a equipe',
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
                      final isInTeam = _isHandlerInTeam(handler['ra']);
                      final isDisabled = isInTeam;
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
                          onTap: isDisabled ? null : () => _addHandler(handler),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDisabled
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
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
                                  )
                                else
                                  IconButton.filledTonal(
                                    tooltip: 'Adicionar integrante',
                                    onPressed: () => _addHandler(handler),
                                    icon: const Icon(
                                      Icons.person_add_alt_1,
                                      size: 20,
                                    ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
