import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfExportService {
  // ─── Colours ──────────────────────────────────────────────────────────────
  static final _green = PdfColor.fromHex('00C48C');
  static final _dark = PdfColor.fromHex('1A1A2E');
  static final _grey = PdfColor.fromHex('8F9BB3');
  static final _lightGrey = PdfColor.fromHex('F7F8FA');
  static final _borderGrey = PdfColor.fromHex('E4E9F2');

  // ─── Mode labels ──────────────────────────────────────────────────────────
  static String _modeLabel(String? mode) {
    switch (mode) {
      case 'cadrer':
        return 'Cadrage';
      case 'produire':
        return 'Production';
      case 'communiquer':
        return 'Communication';
      case 'audit':
        return 'Audit 7 jours';
      default:
        return "Plan d'action";
    }
  }

  static String _footerNote(String? mode) {
    switch (mode) {
      case 'communiquer':
        return 'Utilise ce brouillon comme base, puis adapte le ton et la deadline avant envoi.';
      case 'cadrer':
        return 'Valide ce cadrage avec le client avant de lancer la production.';
      case 'audit':
        return 'Commence par les quick wins à faible effort pour montrer de la traction.';
      default:
        return "Vise un premier livrable partageable rapidement, puis itère.";
    }
  }

  // ─── Section parser (mirrors SummaryView._buildSections) ─────────────────
  static List<_Section> _buildSections({
    required List<String> steps,
    required String? deliveryMode,
    required Map<String, dynamic>? deliveryPlan,
  }) {
    if (deliveryPlan != null && deliveryPlan.isNotEmpty) {
      List<String> listOf(String key) {
        final value = deliveryPlan[key];
        if (value is List) {
          return value
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
        }
        if (value is String && value.trim().isNotEmpty) return [value.trim()];
        return const [];
      }

      final fromPlan = [
        _Section('Objectif', listOf('objective')),
        _Section('Prochaines actions', listOf('nextActions')),
        _Section('Timeline', listOf('timeline')),
        _Section("Critères d'acceptation", listOf('acceptanceCriteria')),
        _Section('Périmètre', listOf('scope')),
        _Section('Risques', listOf('risks')),
        _Section('Effort', listOf('effort')),
        _Section('Dépendances', listOf('dependencies')),
      ].where((s) => s.items.isNotEmpty).toList();

      if (fromPlan.isNotEmpty) return fromPlan;
    }

    final cleanSteps =
        steps.where((s) => s.trim().isNotEmpty).toList();

    switch (deliveryMode) {
      case 'cadrer':
        return [
          _Section('Objectif et contexte', cleanSteps.take(2).toList()),
          _Section('Risques et contraintes',
              cleanSteps.skip(2).take(2).toList()),
          _Section('Définition du livrable', cleanSteps.skip(4).toList()),
        ].where((s) => s.items.isNotEmpty).toList();
      case 'communiquer':
        return [
          _Section('Message principal', cleanSteps.take(2).toList()),
          _Section('Points à partager', cleanSteps.skip(2).take(2).toList()),
          _Section('Call to action', cleanSteps.skip(4).toList()),
        ].where((s) => s.items.isNotEmpty).toList();
      case 'audit':
        return [
          _Section('Constats', cleanSteps.take(2).toList()),
          _Section('Quick wins', cleanSteps.skip(2).take(2).toList()),
          _Section('Plan 7 jours', cleanSteps.skip(4).toList()),
        ].where((s) => s.items.isNotEmpty).toList();
      default:
        return [
          _Section('Priorités', cleanSteps.take(2).toList()),
          _Section('Checklist exécution', cleanSteps.skip(2).take(3).toList()),
          _Section('Livrable final', cleanSteps.skip(5).toList()),
        ].where((s) => s.items.isNotEmpty).toList();
    }
  }

  // ─── Public entry point ───────────────────────────────────────────────────
  static Future<void> exportAndShare({
    required String title,
    required List<String> steps,
    required String? deliveryMode,
    required Map<String, dynamic>? deliveryPlan,
    required String? source,
  }) async {
    final bytes = await _buildPdf(
      title: title,
      steps: steps,
      deliveryMode: deliveryMode,
      deliveryPlan: deliveryPlan,
      source: source,
    );
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .substring(0, title.length.clamp(0, 30));
    await Printing.sharePdf(bytes: bytes, filename: 'hackit_$slug.pdf');
  }

  // ─── PDF builder ──────────────────────────────────────────────────────────
  static Future<Uint8List> _buildPdf({
    required String title,
    required List<String> steps,
    required String? deliveryMode,
    required Map<String, dynamic>? deliveryPlan,
    required String? source,
  }) async {
    final pdf = pw.Document();
    final sections = _buildSections(
      steps: steps,
      deliveryMode: deliveryMode,
      deliveryPlan: deliveryPlan,
    );
    final modeLabel = _modeLabel(deliveryMode);
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    // Strategy variants
    final rawVariants = deliveryPlan?['strategyVariants'];
    final variants =
        rawVariants is List ? rawVariants.whereType<Map>().toList() : <Map>[];

    // ReadyToSend
    final readyToSendRaw = deliveryPlan?['readyToSend'];
    final readyToSend = readyToSendRaw is String &&
            readyToSendRaw.trim().isNotEmpty
        ? readyToSendRaw.trim()
        : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        header: (ctx) => _header(ctx, modeLabel, dateStr),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          _titleWidget(title, source),
          pw.SizedBox(height: 24),
          if (variants.isNotEmpty) ...[
            _sectionTitle('Stratégies disponibles'),
            pw.SizedBox(height: 8),
            ...variants.map((v) => _variantBlock(v)),
            pw.SizedBox(height: 16),
          ],
          ...sections.expand(
              (s) => [_sectionBlock(s.title, s.items), pw.SizedBox(height: 12)]),
          if (readyToSend != null) ...[
            pw.SizedBox(height: 4),
            _readyToSendBlock(readyToSend, modeLabel),
            pw.SizedBox(height: 12),
          ],
          pw.SizedBox(height: 8),
          _noteBox(_footerNote(deliveryMode)),
        ],
      ),
    );

    return pdf.save();
  }

  // ─── Header ───────────────────────────────────────────────────────────────
  static pw.Widget _header(pw.Context ctx, String modeLabel, String date) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  width: 8,
                  height: 8,
                  decoration: pw.BoxDecoration(
                    color: _green,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Text(
                  'Hackit',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _dark,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: _green,
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                  child: pw.Text(
                    modeLabel,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ],
            ),
            pw.Text(
              date,
              style: pw.TextStyle(fontSize: 10, color: _grey),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: _borderGrey, thickness: 1),
        pw.SizedBox(height: 4),
      ],
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────────
  static pw.Widget _footer(pw.Context ctx) {
    return pw.Column(
      children: [
        pw.Divider(color: _borderGrey, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Généré par Hackit — confidentiel',
              style: pw.TextStyle(fontSize: 8, color: _grey),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: _grey),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Title block ──────────────────────────────────────────────────────────
  static pw.Widget _titleWidget(String title, String? source) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: _dark,
          ),
        ),
        if (source != null && source.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            source,
            style: pw.TextStyle(fontSize: 10, color: _grey),
          ),
        ],
        pw.SizedBox(height: 6),
        pw.Container(height: 3, width: 40, color: _green),
      ],
    );
  }

  // ─── Section title ────────────────────────────────────────────────────────
  static pw.Widget _sectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: _dark,
      ),
    );
  }

  // ─── Section block ────────────────────────────────────────────────────────
  static pw.Widget _sectionBlock(String title, List<String> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 3,
              height: 14,
              margin: const pw.EdgeInsets.only(right: 8),
              decoration: pw.BoxDecoration(
                color: _green,
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _dark,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        ...items.asMap().entries.map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 18,
                      height: 18,
                      margin: const pw.EdgeInsets.only(right: 8, top: 1),
                      decoration: pw.BoxDecoration(
                        color: _dark,
                        shape: pw.BoxShape.circle,
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        '${e.key + 1}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        e.value,
                        style: pw.TextStyle(
                          fontSize: 11,
                          lineSpacing: 2,
                          color: _dark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // ─── Strategy variant block ───────────────────────────────────────────────
  static pw.Widget _variantBlock(Map variant) {
    final name = variant['name']?.toString() ?? '';
    final recommended = variant['recommended'] == true;
    final gains = (variant['estimatedGains'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final risks = (variant['risks'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final effort = variant['effort']?.toString();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: recommended ? PdfColor.fromHex('F0FDF8') : _lightGrey,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(
          color: recommended ? _green : _borderGrey,
          width: recommended ? 1.5 : 0.5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  name,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _dark,
                  ),
                ),
              ),
              if (recommended)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: _green,
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                  child: pw.Text(
                    'Recommandé',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
            ],
          ),
          if (effort != null) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Effort: $effort',
              style: pw.TextStyle(fontSize: 10, color: _grey),
            ),
          ],
          if (gains.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Gains: ${gains.join(' · ')}',
              style: pw.TextStyle(fontSize: 10, color: _dark),
            ),
          ],
          if (risks.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Risques: ${risks.join(' · ')}',
              style: pw.TextStyle(fontSize: 10, color: _grey),
            ),
          ],
        ],
      ),
    );
  }

  // ─── ReadyToSend block ────────────────────────────────────────────────────
  static pw.Widget _readyToSendBlock(String text, String modeLabel) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('EFF8FF'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('C7E3FF'), width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Prêt à envoyer — $modeLabel',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('0070C0'),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 11,
              lineSpacing: 2,
              color: _dark,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Note box ─────────────────────────────────────────────────────────────
  static pw.Widget _noteBox(String note) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _lightGrey,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        note,
        style: pw.TextStyle(
          fontSize: 10,
          lineSpacing: 2,
          color: _grey,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    );
  }
}

// ─── Internal data class ────────────────────────────────────────────────────
class _Section {
  final String title;
  final List<String> items;
  const _Section(this.title, this.items);
}
