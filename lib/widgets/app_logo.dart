import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.hardEdge,
          child: const Icon(Icons.coffee, color: Colors.black),
        ),
        const SizedBox(width: 12),
        const Text(
          'Pro Profit',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
