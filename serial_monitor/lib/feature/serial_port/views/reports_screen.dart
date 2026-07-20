import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/config/app_constants.dart';
import '../../../utils/theme/app_theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ScrollController _scrollController = ScrollController();
  final HttpClient _httpClient = HttpClient();
  
  List<dynamic> _records = [];
  List<String> _serialNumbers = ['All'];
  String _selectedSerial = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  
  String? _nextCursor;
  bool _isLoading = false;
  bool _isInitialLoading = true;
  
  // Summary Stats
  int _totalTests = 0;
  int _passed = 0;
  int _failed = 0;
  double _passRate = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchSerialNumbers();
    _fetchData(isRefresh: true);
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
        _fetchData(isRefresh: false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _httpClient.close();
    super.dispose();
  }

  Future<void> _fetchSerialNumbers() async {
    try {
      final request = await _httpClient.getUrl(Uri.parse('${AppConstants.apiBaseUrl}/tests/serial-numbers'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        if (json['success'] == true) {
          final List<dynamic> list = json['serialNumbers'];
          setState(() {
            _serialNumbers = ['All', ...list.map((e) => e.toString())];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchData({required bool isRefresh}) async {
    if (_isLoading) return;
    if (!isRefresh && _nextCursor == null) return;

    setState(() {
      _isLoading = true;
      if (isRefresh) _isInitialLoading = true;
    });

    try {
      final queryParams = <String, String>{
        'limit': '30',
      };
      if (_selectedSerial != 'All') {
        queryParams['serialNumber'] = _selectedSerial;
      }
      if (_startDate != null) {
        queryParams['startDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
      }
      if (_endDate != null) {
        queryParams['endDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
      }
      if (!isRefresh && _nextCursor != null) {
        queryParams['cursor'] = _nextCursor!;
      }

      final uri = Uri.http('${AppConstants.backendHost}:${AppConstants.backendPort}', '/api/tests', queryParams);
      final request = await _httpClient.getUrl(uri);
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        
        if (json['success'] == true) {
          final List<dynamic> newRecords = json['records'];
          setState(() {
            if (isRefresh) {
              _records = newRecords;
            } else {
              _records.addAll(newRecords);
            }
            _nextCursor = json['nextCursor'];
            _calculateStats();
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load reports from backend.', style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _isInitialLoading = false;
      });
    }
  }

  void _calculateStats() {
    _totalTests = _records.length;
    _passed = _records.where((r) => r['result'] == 'success').length;
    _failed = _totalTests - _passed;
    _passRate = _totalTests > 0 ? (_passed / _totalTests) * 100 : 0.0;
  }

  void _resetFilters() {
    setState(() {
      _selectedSerial = 'All';
      _startDate = null;
      _endDate = null;
    });
    _fetchData(isRefresh: true);
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => _buildThemeDatePicker(child),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
      _fetchData(isRefresh: true);
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => _buildThemeDatePicker(child),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
      _fetchData(isRefresh: true);
    }
  }

  Widget _buildThemeDatePicker(Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.primaryColor,
          onPrimary: Colors.white,
          surface: AppTheme.bgMedium,
          onSurface: AppTheme.textPrimary,
        ),
        dialogBackgroundColor: AppTheme.bgDarkest,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  Future<void> _printReport() async {
    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records to print.')),
      );
      return;
    }

    final doc = pw.Document();

    // Load fonts
    final font = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();

    // Generate 1 Page per Serial Number
    for (final rec in _records) {
      final serial = rec['serialNumber']?.toString() ?? 'N/A';
      final boardType = rec['boardType']?.toString() ?? (rec['paramType']?.toString().toUpperCase() ?? 'N/A');
      final dateStr = rec['timestamp'] != null 
          ? DateFormat('MM/dd/yyyy HH:mm:ss').format(DateTime.parse(rec['timestamp'])) 
          : 'N/A';
      
      final isOverallPass = rec['result'] == 'success' || rec['result'] == 'PASS';
      final resultColor = isOverallPass ? PdfColors.green700 : PdfColors.red700;
      final resultBg = isOverallPass ? PdfColors.green50 : PdfColors.red50;
      final resultText = isOverallPass ? 'PASS' : 'FAIL';

      final List<dynamic> testRows = rec['testRows'] is List ? rec['testRows'] : [];

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header Row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('RDPMS QUALITY CONTROL TEST REPORT', style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.blueGrey900)),
                        pw.SizedBox(height: 2),
                        pw.Text('Device Verification & Quality Assurance Certificate', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('RDPMS AUTOMATION', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blue800)),
                        pw.Text('Date: ${DateFormat('MM/dd/yyyy').format(DateTime.now())}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 1.5, color: PdfColors.blue800),
                pw.SizedBox(height: 12),

                // Device Specification & Result Summary Card
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('SERIAL NUMBER: ', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey700)),
                              pw.Text(serial, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blueGrey900)),
                            ],
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text('Board / Test Profile: $boardType', style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.grey800)),
                          pw.SizedBox(height: 2),
                          pw.Text('Tested At: $dateStr', style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey600)),
                        ],
                      ),
                      // Pass / Fail Status Badge
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: resultBg,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                          border: pw.Border.all(color: resultColor, width: 1.2),
                        ),
                        child: pw.Text(
                          'QC RESULT: $resultText',
                          style: pw.TextStyle(font: fontBold, fontSize: 12, color: resultColor),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),

                pw.Text('Multi-Reference Point Verification Details:', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.blueGrey900)),
                pw.SizedBox(height: 6),

                // Table of Reference Rows
                if (testRows.isNotEmpty)
                  pw.TableHelper.fromTextArray(
                    headers: ['#', 'Ref Point', 'Tol (%)', 'CH1 Value', 'CH1 Status', 'CH2 Value', 'CH2 Status', 'Overall'],
                    data: testRows.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final r = entry.value;
                      final unit = boardType.toLowerCase().contains('current') ? ' A' : ' V';
                      
                      final refStr = '${r['ref'] ?? 0.0}$unit';
                      final tolStr = '${r['tolerance'] ?? 1.0}%';

                      final ch1ValStr = r['useCh1'] == true && r['ch1Value'] != null ? '${r['ch1Value']}$unit' : 'OFF';
                      final ch1ResStr = r['useCh1'] == true ? (r['ch1Result'] ?? 'PENDING') : 'OFF';

                      final ch2ValStr = r['useCh2'] == true && r['ch2Value'] != null ? '${r['ch2Value']}$unit' : 'OFF';
                      final ch2ResStr = r['useCh2'] == true ? (r['ch2Result'] ?? 'PENDING') : 'OFF';

                      final overallStr = r['result'] ?? 'PENDING';

                      return [
                        '#$idx',
                        refStr,
                        tolStr,
                        ch1ValStr,
                        ch1ResStr,
                        ch2ValStr,
                        ch2ResStr,
                        overallStr,
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                    cellStyle: pw.TextStyle(font: font, fontSize: 8),
                    cellAlignment: pw.Alignment.centerLeft,
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  )
                else
                  pw.TableHelper.fromTextArray(
                    headers: ['Target Value', 'Tolerance (%)', 'Measured Value', 'Result'],
                    data: [
                      [
                        '${rec['targetValue'] ?? "N/A"}',
                        '${rec['tolerance'] ?? "1.0"}%',
                        '${rec['paramValue'] ?? "N/A"}',
                        isOverallPass ? 'PASS' : 'FAIL',
                      ]
                    ],
                    headerStyle: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                    cellStyle: pw.TextStyle(font: font, fontSize: 8),
                    cellAlignment: pw.Alignment.centerLeft,
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  ),

                pw.Spacer(),

                // Bottom Footer: System info on left, Bottom-Right Signature Box on right
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('RDPMS Quality Control System - Official Certificate', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey700)),
                        pw.Text('This report is electronically generated and logged into Atlas Database.', style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey600)),
                      ],
                    ),
                    // Verified By Signature Box (Bottom Right)
                    pw.Container(
                      width: 190,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        color: PdfColors.grey50,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('VERIFIED BY:', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.blueGrey900)),
                          pw.SizedBox(height: 10),
                          pw.Text('Name: ______________________', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.blueGrey800)),
                          pw.SizedBox(height: 6),
                          pw.Text('Sign:  ______________________', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.blueGrey800)),
                          pw.SizedBox(height: 6),
                          pw.Text('Date:  ______________________', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.blueGrey800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'RDPMS_QC_Report_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
    );
  }

  pw.Widget _buildPdfStatCard(String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.Container(
      width: 100,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.blueGrey900)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDarkest,
      appBar: AppBar(
        backgroundColor: AppTheme.panelHeader,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Verification Reports & History',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textBright,
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: _printReport,
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
            label: Text('Print PDF', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: const BorderSide(color: AppTheme.primaryColor),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
          const SizedBox(width: 15),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Filters Panel
              SizedBox(
                width: 280,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.bgMedium,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.filter_list_rounded, size: 16, color: AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Filters',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textBright),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: AppTheme.borderColor),
                      const SizedBox(height: 16),
                      
                      // Serial Number
                      _buildLabel('Serial Number'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedSerial,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedSerial = val;
                            });
                            _fetchData(isRefresh: true);
                          }
                        },
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textBright),
                        dropdownColor: AppTheme.bgElevated,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        items: _serialNumbers.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s),
                        )).toList(),
                      ),
                      const SizedBox(height: 20),

                      // Start Date
                      _buildLabel('Start Date'),
                      const SizedBox(height: 6),
                      OutlinedButton(
                        onPressed: () => _selectStartDate(context),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          side: const BorderSide(color: AppTheme.borderColor),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _startDate != null ? DateFormat('MM/dd/yyyy').format(_startDate!) : 'Select Start Date',
                              style: GoogleFonts.inter(fontSize: 12, color: _startDate != null ? AppTheme.textBright : AppTheme.textMuted),
                            ),
                            const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.textMuted),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // End Date
                      _buildLabel('End Date'),
                      const SizedBox(height: 6),
                      OutlinedButton(
                        onPressed: () => _selectEndDate(context),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          side: const BorderSide(color: AppTheme.borderColor),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _endDate != null ? DateFormat('MM/dd/yyyy').format(_endDate!) : 'Select End Date',
                              style: GoogleFonts.inter(fontSize: 12, color: _endDate != null ? AppTheme.textBright : AppTheme.textMuted),
                            ),
                            const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.textMuted),
                          ],
                        ),
                      ),
                      
                      const Spacer(),
                      OutlinedButton(
                        onPressed: _resetFilters,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          side: const BorderSide(color: AppTheme.borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Clear Filters', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Stats + Table content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Stats Grid Row
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('TOTAL TESTS', _totalTests.toString(), null)),
                        const SizedBox(width: 14),
                        Expanded(child: _buildStatCard('PASSED', _passed.toString(), AppTheme.successColor)),
                        const SizedBox(width: 14),
                        Expanded(child: _buildStatCard('FAILED', _failed.toString(), AppTheme.errorColor)),
                        const SizedBox(width: 14),
                        Expanded(child: _buildStatCard('PASS RATE', '${_passRate.toStringAsFixed(1)}%', AppTheme.accentOrange)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Table Card
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.bgMedium,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: _isInitialLoading
                            ? const Center(
                                child: CircularProgressIndicator(color: AppTheme.primaryColor),
                              )
                            : _records.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.receipt_long_rounded, size: 48, color: AppTheme.textMuted),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No Records Found',
                                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                                        ),
                                        Text(
                                          'No quality control records match filters.',
                                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    children: [
                                      // Table Header
                                      Container(
                                        height: 38,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.panelHeader,
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(11),
                                            topRight: Radius.circular(11),
                                          ),
                                          border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
                                        ),
                                        child: Row(
                                          children: [
                                            _buildTableHeaderCell('Date & Time', 130),
                                            _buildTableHeaderCell('Serial Number', 110),
                                            _buildTableHeaderCell('Type', 80),
                                            _buildTableHeaderCell('Target', 80),
                                            _buildTableHeaderCell('Tolerance', 80),
                                            _buildTableHeaderCell('Measured', 90),
                                            Expanded(child: _buildTableHeaderCell('Result', 80)),
                                          ],
                                        ),
                                      ),
                                      // Table Body
                                      Expanded(
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          itemCount: _records.length + (_isLoading ? 1 : 0),
                                          itemBuilder: (context, index) {
                                            if (index == _records.length) {
                                              return const Padding(
                                                padding: EdgeInsets.all(16),
                                                child: Center(
                                                  child: SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                                                  ),
                                                ),
                                              );
                                            }
                                            final rec = _records[index];
                                            return _buildTableRow(rec, index.isEven);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color? sidebarColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgMedium,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Stack(
        children: [
          if (sidebarColor != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: sidebarColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(left: sidebarColor != null ? 12 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textBright)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, double? width) {
    final cell = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
    if (width == null) return cell;
    return SizedBox(width: width, child: cell);
  }

  Widget _buildTableRow(dynamic rec, bool isEven) {
    final date = DateTime.parse(rec['timestamp']);
    final dateStr = DateFormat('MM/dd/yy HH:mm').format(date);
    
    final type = rec['paramType']?.toString().toUpperCase() ?? 'N/A';
    final unit = type == 'CURRENT' ? ' A' : ' V';
    final isPass = rec['result'] == 'success';
    
    final target = rec['targetValue'] != null ? '${rec['targetValue']}$unit' : 'N/A';
    final tolerance = rec['tolerance'] != null ? '${rec['tolerance']}%' : 'N/A';
    final measured = '${rec['paramValue']}$unit';

    Color resultColor = isPass ? AppTheme.successColor : AppTheme.errorColor;
    
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isEven ? AppTheme.bgDarkest.withValues(alpha: 0.2) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: AppTheme.borderColor, width: 0.5)),
      ),
      child: Row(
        children: [
          // Date & Time
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(dateStr, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textPrimary)),
            ),
          ),
          // Serial Number
          SizedBox(
            width: 110,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(rec['serialNumber']?.toString() ?? 'N/A', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textPrimary)),
            ),
          ),
          // Type
          SizedBox(
            width: 80,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(type, style: GoogleFonts.inter(fontSize: 11, color: type == 'CURRENT' ? AppTheme.accentOrange : AppTheme.primaryColor, fontWeight: FontWeight.bold)),
            ),
          ),
          // Target
          SizedBox(
            width: 80,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(target, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textSecondary)),
            ),
          ),
          // Tolerance
          SizedBox(
            width: 80,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(tolerance, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textSecondary)),
            ),
          ),
          // Measured
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(measured, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textBright, fontWeight: FontWeight.bold)),
            ),
          ),
          // Result
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: resultColor),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPass ? 'PASS' : 'FAIL',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: resultColor, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
