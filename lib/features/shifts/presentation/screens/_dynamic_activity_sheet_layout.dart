part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _DynamicActivitySheetLayout on _DynamicActivitySheetState {
  Widget _buildFormScaffold() {
    if (_isOccurrenceCategory) {
      return _buildOccurrenceFormScaffold();
    }

    return ActivityFormScaffold(
      title: _selectedSubtype?.toUpperCase() ?? '',
      imagePath: _selectedSubtypeImagePath,
      heroTag: _selectedSubtype == null
          ? null
          : 'hero_category_$_selectedSubtype',
      isSaving: _isSaving,
      onBack: _handleStandardFormBack,
      child: _buildFormContent(),
    );
  }

  void _handleStandardFormBack() {
    if (widget.fullScreen || widget.initialData != null) {
      _closeForm(false);
      return;
    }

    final savedPage = _currentMenuPage;
    setState(() {
      _showMenu = true;
      _selectedSubtype = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_menuPageController.hasClients) {
        _menuPageController.jumpToPage(savedPage);
      }
    });
  }

  Widget _buildMenuSheet(BuildContext context) {
    if (_currentMenuPage >= _currentCategoryCards.length) {
      _currentMenuPage = 0;
    }

    return ActivityCategoryMenuSheet(
      cards: _currentCategoryCards,
      currentPage: _currentMenuPage,
      pageController: _menuPageController,
      onPageChanged: (index) {
        HapticFeedback.selectionClick();
        setState(() => _currentMenuPage = index);
      },
      onCardConfirmed: (card) =>
          _selectSubtype(card['id'], imagePath: card['image']),
    );
  }

  Color _getCategoryColor() {
    if (_isOccurrenceCategory) {
      if (_occurrenceStatus == OccurrenceFormController.statusCanceled) {
        return _kHudRed;
      }
      if (_occurrenceStatus == OccurrenceFormController.statusCompleted) {
        return _kHudGreen;
      }
      return _kHudCyan;
    }
    return ActivityCardCatalog.glowFor(
      category: widget.category,
      id: _selectedSubtype,
      fallback: const Color(0xFF1B8A4C),
    );
  }

  Widget _buildFormContent() {
    final tColor = _getCategoryColor();
    if (_isOccurrenceCategory) {
      return _buildOccurrenceStepperContent(tColor);
    }
    if (_selectedSubtype == ActivitySubtypeIds.detection ||
        _selectedSubtype == ActivitySubtypeIds.missingPerson) {
      return _buildGroupedFormContent(tColor);
    }
    return _buildStandardFormContent(tColor);
  }
}
