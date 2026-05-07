import 'package:flutter/material.dart';

class ActivityFormBody extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  const ActivityFormBody({
    super.key,
    required this.formKey,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: crossAxisAlignment,
          children: children,
        ),
      ),
    );
  }
}
