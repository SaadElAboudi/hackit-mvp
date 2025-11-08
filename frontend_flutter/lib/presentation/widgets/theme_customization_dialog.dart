import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class ThemeCustomizationDialog extends StatefulWidget {
  final ThemeService themeService;
  final CustomThemeData? currentTheme;

  const ThemeCustomizationDialog({
    super.key,
    required this.themeService,
    this.currentTheme,
  });

  @override
  _ThemeCustomizationDialogState createState() =>
      _ThemeCustomizationDialogState();
}

class _ThemeCustomizationDialogState extends State<ThemeCustomizationDialog> {
  late Color _primaryColor;
  late Color _accentColor;
  late double _borderRadius;
  late double _elevation;

  @override
  void initState() {
    super.initState();
    _primaryColor = widget.currentTheme?.primaryColor ?? Colors.blue;
    _accentColor = widget.currentTheme?.accentColor ?? Colors.blueAccent;
    _borderRadius = widget.currentTheme?.borderRadius ?? 8.0;
    _elevation = widget.currentTheme?.elevation ?? 2.0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Personnaliser le thème'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildColorPicker(
              'Couleur principale',
              _primaryColor,
              (color) => setState(() => _primaryColor = color),
            ),
            const SizedBox(height: 16),
            _buildColorPicker(
              'Couleur secondaire',
              _accentColor,
              (color) => setState(() => _accentColor = color),
            ),
            const SizedBox(height: 16),
            _buildSlider(
              'Bordures arrondies',
              _borderRadius,
              0.0,
              24.0,
              (value) => setState(() => _borderRadius = value),
            ),
            const SizedBox(height: 16),
            _buildSlider(
              'Élévation',
              _elevation,
              0.0,
              8.0,
              (value) => setState(() => _elevation = value),
            ),
            const SizedBox(height: 16),
            _buildPreview(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _saveTheme,
          child: const Text('Appliquer'),
        ),
      ],
    );
  }

  Widget _buildColorPicker(
    String label,
    Color currentColor,
    ValueChanged<Color> onColorChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showColorPicker(
            context,
            currentColor,
            onColorChanged,
          ),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 2).toInt(),
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            'Aperçu',
            style: TextStyle(
              color: _primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: _elevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_borderRadius),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.palette, color: _accentColor),
                  const SizedBox(width: 8),
                  Text(
                    'Exemple de composant',
                    style: TextStyle(color: _primaryColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color> onColorChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choisir une couleur'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: onColorChanged,
            portraitOnly: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _saveTheme() {
    final customTheme = CustomThemeData(
      primaryColor: _primaryColor,
      accentColor: _accentColor,
      borderRadius: _borderRadius,
      elevation: _elevation,
    );
    widget.themeService.saveCustomTheme(customTheme);
    Navigator.of(context).pop();
  }
}