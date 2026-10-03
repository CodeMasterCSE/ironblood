import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class InvoiceLineItem {
  final String description;
  final String category;
  final String? coachOrDetails;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final double amount;

  InvoiceLineItem({
    required this.description,
    required this.category,
    this.coachOrDetails,
    this.startDate,
    this.expiryDate,
    required this.amount,
  });
}

class InvoiceModel {
  final String invoiceNo;
  final DateTime invoiceDate;
  final String memberId;
  final String memberName;
  final String memberPhone;
  final String memberEmail;
  final String
  category; // 'MEMBERSHIP ENROLLMENT', 'MEMBERSHIP RENEWAL', 'PERSONAL TRAINING (PT)'
  final String planName;
  final String? trainerName;
  final DateTime startDate;
  final DateTime expiryDate;
  final double basePrice;
  final double discountAmount;
  final double finalAmount;
  final String paymentMode; // 'UPI', 'Cash', 'Card'
  final String? notes;
  final List<InvoiceLineItem> items;

  InvoiceModel({
    required this.invoiceNo,
    required this.invoiceDate,
    required this.memberId,
    required this.memberName,
    String? memberPhone,
    String? memberEmail,
    required this.category,
    required this.planName,
    this.trainerName,
    DateTime? startDate,
    DateTime? expiryDate,
    double? basePrice,
    double? baseAmount,
    this.discountAmount = 0.0,
    required this.finalAmount,
    this.paymentMode = 'UPI',
    this.notes,
    List<InvoiceLineItem>? items,
  }) : memberPhone = memberPhone ?? '',
       memberEmail = memberEmail ?? '',
       startDate = startDate ?? invoiceDate,
       expiryDate = expiryDate ?? invoiceDate.add(const Duration(days: 30)),
       basePrice = basePrice ?? baseAmount ?? finalAmount,
       items = (items != null && items.isNotEmpty)
           ? items
           : [
               InvoiceLineItem(
                 description: planName,
                 category: category,
                 coachOrDetails:
                     (trainerName != null &&
                         trainerName.isNotEmpty &&
                         trainerName != 'Unassigned')
                     ? 'Dedicated Coach: '
                     : null,
                 startDate: startDate ?? invoiceDate,
                 expiryDate:
                     expiryDate ?? invoiceDate.add(const Duration(days: 30)),
                 amount: basePrice ?? baseAmount ?? finalAmount,
               ),
             ];

  static String generateInvoiceNo({String prefix = 'INV'}) {
    final now = DateTime.now();
    final datePart =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    final randPart = (now.millisecondsSinceEpoch % 10000).toString().padLeft(
      4,
      '0',
    );
    return "IB-$prefix-$datePart-$randPart";
  }
}

class InvoiceService {
  // Brand Palette for PDF (CMYK/Hex approximate in PDF format)
  static const PdfColor pdfGold = PdfColor.fromInt(0xFFC9A227);
  static const PdfColor pdfDarkGreen = PdfColor.fromInt(0xFF091911);
  static const PdfColor pdfCardGreen = PdfColor.fromInt(0xFF0F261B);
  static const PdfColor pdfEmerald = PdfColor.fromInt(0xFF10B981);
  static const PdfColor pdfLightGold = PdfColor.fromInt(0xFFFFE082);
  static const PdfColor pdfTextGrey = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor pdfBorderColor = PdfColor.fromInt(0xFF1E4230);

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return "${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}";
  }

  static String _formatCurrency(double amount) {
    final int val = amount.round();
    final str = val.toString();
    if (str.length <= 3) return 'Rs. $str';
    final last3 = str.substring(str.length - 3);
    final remaining = str.substring(0, str.length - 3);
    final formattedRemaining = remaining.replaceAllMapped(
      RegExp(r'(\d)(?=(\d\d)+$)'),
      (m) => '${m[1]},',
    );
    return 'Rs. $formattedRemaining,$last3';
  }

  static String _numberToWords(int number) {
    if (number == 0) return "Zero";
    final units = [
      "",
      "One",
      "Two",
      "Three",
      "Four",
      "Five",
      "Six",
      "Seven",
      "Eight",
      "Nine",
      "Ten",
      "Eleven",
      "Twelve",
      "Thirteen",
      "Fourteen",
      "Fifteen",
      "Sixteen",
      "Seventeen",
      "Eighteen",
      "Nineteen",
    ];
    final tens = [
      "",
      "",
      "Twenty",
      "Thirty",
      "Forty",
      "Fifty",
      "Sixty",
      "Seventy",
      "Eighty",
      "Ninety",
    ];

    String convertLessThanOneThousand(int n) {
      if (n == 0) return "";
      if (n < 20) return "${units[n]} ";
      if (n < 100) {
        return "${tens[n ~/ 10]} ${convertLessThanOneThousand(n % 10)}";
      }
      return "${units[n ~/ 100]} Hundred ${convertLessThanOneThousand(n % 100)}";
    }

    int n = number;
    String result = "";

    if (n >= 10000000) {
      result += "${convertLessThanOneThousand(n ~/ 10000000)}Crore ";
      n %= 10000000;
    }
    if (n >= 100000) {
      result += "${convertLessThanOneThousand(n ~/ 100000)}Lakh ";
      n %= 100000;
    }
    if (n >= 1000) {
      result += "${convertLessThanOneThousand(n ~/ 1000)}Thousand ";
      n %= 1000;
    }
    result += convertLessThanOneThousand(n);
    return result.trim();
  }

  /// Generate Formal Tax Invoice & Payment Receipt PDF Document Bytes
  static Future<Uint8List> generatePdf(InvoiceModel invoice) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('lib/logo.png');
      final uint8List = byteData.buffer.asUint8List();
      logoImage = pw.MemoryImage(uint8List);
    } catch (e) {
      debugPrint("Could not load logo for invoice: $e");
    }

    const formalNavy = PdfColor.fromInt(0xFF0F172A);
    const formalDark = PdfColor.fromInt(0xFF1E293B);
    const formalGold = PdfColor.fromInt(0xFF9A7B2C);
    const formalMuted = PdfColor.fromInt(0xFF64748B);
    const formalBorder = PdfColor.fromInt(0xFFCBD5E1);
    const formalBg = PdfColor.fromInt(0xFFF8FAFC);
    const formalEmerald = PdfColor.fromInt(0xFF047857);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ===================================================
              // 1. FORMAL HEADER
              // ===================================================
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoImage != null) ...[
                        pw.Container(
                          width: 52,
                          height: 52,
                          margin: const pw.EdgeInsets.only(right: 12),
                          padding: const pw.EdgeInsets.all(4),
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            color: const PdfColor.fromInt(0xFF09140E),
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(6),
                            ),
                            border: pw.Border.all(
                              color: formalGold,
                              width: 1.5,
                            ),
                          ),
                          child: pw.Center(
                            child: pw.ClipRRect(
                              horizontalRadius: 4,
                              verticalRadius: 4,
                              child: pw.Image(
                                logoImage,
                                fit: pw.BoxFit.contain,
                                alignment: pw.Alignment.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            "IRONBLOOD",
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                              color: formalNavy,
                              letterSpacing: 2.0,
                            ),
                          ),
                          pw.Text(
                            "MUSCLE & FITNESS STUDIO",
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: formalGold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            "50, Bansdroni Park, Ward Number 113,",
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: formalMuted,
                            ),
                          ),
                          pw.Text(
                            "Kolkata, West Bengal 700070, India",
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: formalMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: pw.BoxDecoration(
                          color: formalNavy,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(3),
                          ),
                        ),
                        child: pw.Text(
                          "TAX INVOICE / RECEIPT",
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        "ORIGINAL FOR RECIPIENT",
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: formalMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.RichText(
                        text: pw.TextSpan(
                          text: "Invoice No: ",
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: formalMuted,
                          ),
                          children: [
                            pw.TextSpan(
                              text: invoice.invoiceNo,
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: formalNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.RichText(
                        text: pw.TextSpan(
                          text: "Date of Issue: ",
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: formalMuted,
                          ),
                          children: [
                            pw.TextSpan(
                              text: _formatDate(invoice.invoiceDate),
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: formalNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 12),
              pw.Divider(color: formalNavy, thickness: 1.2),
              pw.SizedBox(height: 12),

              // ===================================================
              // 2. ISSUER & RECIPIENT DETAILS (TWO FORMAL BOXES)
              // ===================================================
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Issuer / Studio Info
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: formalBg,
                        border: pw.Border.all(color: formalBorder, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            "ISSUED BY (SERVICE PROVIDER)",
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: formalGold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            "IRONBLOOD MUSCLE & FITNESS STUDIO",
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: formalNavy,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            "Category: Physical Fitness Centre Services",
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: formalMuted,
                            ),
                          ),
                          pw.Text(
                            "Mobile: +91 82820 72600",
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: formalMuted,
                            ),
                          ),
                          pw.Text(
                            "Email: ironbloodmuscleandfitness@gmail.com",
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: formalMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(width: 12),

                  // Right: Billed To (Member Info)
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: formalBg,
                        border: pw.Border.all(color: formalBorder, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            "BILLED TO (ATHLETE / RECIPIENT)",
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: formalGold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            invoice.memberName.toUpperCase(),
                            style: pw.TextStyle(
                              fontSize: 10.5,
                              fontWeight: pw.FontWeight.bold,
                              color: formalNavy,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            "Member ID: ${invoice.memberId}",
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: formalMuted,
                            ),
                          ),
                          if (invoice.memberPhone.isNotEmpty)
                            pw.Text(
                              "Mobile: ${invoice.memberPhone}",
                              style: const pw.TextStyle(
                                fontSize: 8.5,
                                color: formalMuted,
                              ),
                            ),
                          if (invoice.memberEmail.isNotEmpty)
                            pw.Text(
                              "Email: ${invoice.memberEmail}",
                              style: const pw.TextStyle(
                                fontSize: 8.5,
                                color: formalMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 16),

              // ===================================================
              // 3. FORMAL ITEMIZED SERVICES TABLE
              // ===================================================
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: formalBorder, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  children: [
                    // Table Header
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      color: formalDark,
                      child: pw.Row(
                        children: [
                          pw.SizedBox(
                            width: 25,
                            child: pw.Text(
                              "#",
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 6,
                            child: pw.Text(
                              "DESCRIPTION OF SERVICES",
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 4,
                            child: pw.Text(
                              "VALIDITY / PERIOD",
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                          pw.SizedBox(
                            width: 85,
                            child: pw.Text(
                              "AMOUNT (INR)",
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Table Item Rows
                    ...invoice.items.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final item = entry.value;
                      final isLast = idx == invoice.items.length;
                      final rowBg = idx.isEven
                          ? const PdfColor.fromInt(0xFFF8FAFC)
                          : PdfColors.white;
                      return pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: pw.BoxDecoration(
                          color: rowBg,
                          border: !isLast
                              ? const pw.Border(
                                  bottom: pw.BorderSide(
                                    color: formalBorder,
                                    width: 0.5,
                                  ),
                                )
                              : null,
                        ),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.SizedBox(
                              width: 25,
                              child: pw.Text(
                                "$idx",
                                style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: formalNavy,
                                ),
                              ),
                            ),
                            pw.Expanded(
                              flex: 6,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    item.description,
                                    style: pw.TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: pw.FontWeight.bold,
                                      color: formalNavy,
                                    ),
                                  ),
                                  pw.SizedBox(height: 1),
                                  pw.Text(
                                    "Type: ${item.category}",
                                    style: const pw.TextStyle(
                                      fontSize: 7.5,
                                      color: formalMuted,
                                    ),
                                  ),
                                  if (item.coachOrDetails != null &&
                                      item.coachOrDetails!.isNotEmpty) ...[
                                    pw.SizedBox(height: 1.5),
                                    pw.Text(
                                      item.coachOrDetails!,
                                      style: pw.TextStyle(
                                        fontSize: 8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: formalEmerald,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            pw.Expanded(
                              flex: 4,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  if (item.startDate != null &&
                                      item.expiryDate != null) ...[
                                    pw.Text(
                                      "${_formatDate(item.startDate!)} to",
                                      style: const pw.TextStyle(
                                        fontSize: 8,
                                        color: formalNavy,
                                      ),
                                    ),
                                    pw.Text(
                                      _formatDate(item.expiryDate!),
                                      style: const pw.TextStyle(
                                        fontSize: 8,
                                        color: formalNavy,
                                      ),
                                    ),
                                  ] else ...[
                                    pw.Text(
                                      "${_formatDate(invoice.startDate)} to",
                                      style: const pw.TextStyle(
                                        fontSize: 8,
                                        color: formalNavy,
                                      ),
                                    ),
                                    pw.Text(
                                      _formatDate(invoice.expiryDate),
                                      style: const pw.TextStyle(
                                        fontSize: 8,
                                        color: formalNavy,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            pw.SizedBox(
                              width: 85,
                              child: pw.Text(
                                _formatCurrency(item.amount),
                                textAlign: pw.TextAlign.right,
                                style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: formalNavy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ===================================================
              // 4. AMOUNT IN WORDS & CALCULATION SUMMARY
              // ===================================================
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left side: In words & Payment details
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: formalBg,
                            border: pw.Border.all(
                              color: formalBorder,
                              width: 0.8,
                            ),
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                "TOTAL AMOUNT IN WORDS",
                                style: pw.TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: formalGold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                "Rupees ${_numberToWords(invoice.finalAmount.round())} Only",
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: formalNavy,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: formalBg,
                            border: pw.Border.all(
                              color: formalBorder,
                              width: 0.8,
                            ),
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                "Payment Method: ${invoice.paymentMode.toUpperCase()}",
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: formalNavy,
                                ),
                              ),
                              pw.Text(
                                "Status: Fully Settled & Confirmed",
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: formalEmerald,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 14),

                  // Right side: Breakdown & Total
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: formalBg,
                        border: pw.Border.all(color: formalBorder, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                "Gross Subtotal:",
                                style: const pw.TextStyle(
                                  fontSize: 8.5,
                                  color: formalMuted,
                                ),
                              ),
                              pw.Text(
                                _formatCurrency(invoice.basePrice),
                                style: const pw.TextStyle(
                                  fontSize: 8.5,
                                  color: formalNavy,
                                ),
                              ),
                            ],
                          ),
                          if (invoice.discountAmount > 0) ...[
                            pw.SizedBox(height: 3),
                            pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  "Discount / Concession:",
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    color: formalEmerald,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.Text(
                                  "- ${_formatCurrency(invoice.discountAmount)}",
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    color: formalEmerald,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 4),
                            child: pw.Divider(color: formalBorder, height: 0.8),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: pw.BoxDecoration(
                              color: formalNavy,
                              borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(3),
                              ),
                            ),
                            child: pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  "NET TOTAL PAID:",
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                pw.Text(
                                  _formatCurrency(invoice.finalAmount),
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // ===================================================
              // 5. TERMS & CONDITIONS AND AUTHORIZED SIGNATURE
              // ===================================================
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Terms Box
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "TERMS & CONDITIONS:",
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: formalGold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "1. All memberships and PT subscriptions are non-refundable and non-transferable.\n"
                          "2. Valid digital access pass is mandatory for gym floor entry and facility usage.\n"
                          "3. This is an official computer-generated receipt for physical fitness services.",
                          style: const pw.TextStyle(
                            fontSize: 7,
                            color: formalMuted,
                            lineSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 20),

                  // Signature Block
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          "For IRONBLOOD FITNESS STUDIO",
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: formalNavy,
                          ),
                        ),
                        pw.SizedBox(height: 28),
                        pw.Container(
                          width: 120,
                          height: 0.8,
                          color: formalNavy,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "Authorized Signatory",
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: formalMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 8),
              pw.Divider(color: formalBorder, thickness: 0.8),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  "Thank you for choosing IRONBLOOD Gym & Fitness Studio | Strength | Discipline | Glory",
                  style: const pw.TextStyle(fontSize: 7, color: formalMuted),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Direct download PDF file to device / browser downloads
  static Future<void> downloadPdf(InvoiceModel invoice) async {
    final pdfBytes = await generatePdf(invoice);
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: "IRONBLOOD_Receipt_${invoice.invoiceNo}.pdf",
    );
  }

  /// Print or Save PDF Dialog (Opens native printer/PDF preview on all platforms)
  static Future<void> printOrDownload(
    BuildContext context,
    InvoiceModel invoice,
  ) async {
    final pdfBytes = await generatePdf(invoice);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: "IRONBLOOD_Receipt_${invoice.invoiceNo}.pdf",
    );
  }

  /// Open interactive In-App PDF Viewer (Works 100% on Web, Mobile, Desktop)
  static void openPdfViewer(BuildContext context, InvoiceModel invoice) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: const Color(0xFF091911),
          appBar: AppBar(
            backgroundColor: const Color(0xFF07180F),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Color(0xFFC9A227),
                size: 20,
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "INVOICE #${invoice.invoiceNo}",
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: const Color(0xFFFFE082),
                  ),
                ),
                Text(
                  "${invoice.memberName} • ${invoice.category}",
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.print_rounded, color: Color(0xFFC9A227)),
                tooltip: "Print / Save PDF",
                onPressed: () => printOrDownload(ctx, invoice),
              ),
              IconButton(
                icon: const Icon(
                  Icons.download_rounded,
                  color: Color(0xFFC9A227),
                ),
                tooltip: "Download PDF",
                onPressed: () => downloadPdf(invoice),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: PdfPreview(
            build: (format) => generatePdf(invoice),
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: "IRONBLOOD_Receipt_${invoice.invoiceNo}.pdf",
            previewPageMargin: const EdgeInsets.all(12),
            loadingWidget: const Center(
              child: CircularProgressIndicator(color: Color(0xFFC9A227)),
            ),
          ),
        ),
      ),
    );
  }

  /// Open PDF Viewer on any platform (Web, Android, iOS, Windows, Mac)
  static Future<void> openPdfFile(
    BuildContext context,
    InvoiceModel invoice,
  ) async {
    openPdfViewer(context, invoice);
  }

  /// Format receipt summary text for system share
  static String formatReceiptText(InvoiceModel invoice) {
    final buffer = StringBuffer();
    buffer.writeln("IRONBLOOD GYM & FITNESS STUDIO");
    buffer.writeln("OFFICIAL PAYMENT RECEIPT");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("Invoice No: #${invoice.invoiceNo}");
    buffer.writeln("Date: ${_formatDate(invoice.invoiceDate)}");
    buffer.writeln("Athlete: ${invoice.memberName} (${invoice.memberId})");
    buffer.writeln("Category: ${invoice.category}");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━━━");
    if (invoice.items.length > 1) {
      buffer.writeln("ITEMIZED BILLING:");
      for (int i = 0; i < invoice.items.length; i++) {
        final it = invoice.items[i];
        buffer.writeln(
          " ${i + 1}. ${it.description} - ${_formatCurrency(it.amount)}",
        );
        if (it.coachOrDetails != null && it.coachOrDetails!.isNotEmpty) {
          buffer.writeln("    (${it.coachOrDetails})");
        }
        if (it.startDate != null && it.expiryDate != null) {
          buffer.writeln(
            "    Validity: ${_formatDate(it.startDate!)} to ${_formatDate(it.expiryDate!)}",
          );
        }
      }
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━━━");
    } else {
      buffer.writeln("Plan: ${invoice.planName}");
      if (invoice.trainerName != null &&
          invoice.trainerName!.isNotEmpty &&
          invoice.trainerName != 'Unassigned') {
        buffer.writeln("Dedicated Coach: ${invoice.trainerName}");
      }
      buffer.writeln(
        "Validity: ${_formatDate(invoice.startDate)} to ${_formatDate(invoice.expiryDate)}",
      );
    }
    buffer.writeln("Gross Subtotal: ${_formatCurrency(invoice.basePrice)}");
    if (invoice.discountAmount > 0) {
      buffer.writeln(
        "Discount Applied: - ${_formatCurrency(invoice.discountAmount)}",
      );
    }
    buffer.writeln("Total Paid: ${_formatCurrency(invoice.finalAmount)}");
    buffer.writeln("Payment Mode: ${invoice.paymentMode} (CONFIRMED)");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("Official PDF Bill attached.");
    return buffer.toString();
  }

  /// Share PDF File with formatted text receipt using system share sheet
  static Future<void> sharePdfFile(InvoiceModel invoice) async {
    try {
      final pdfBytes = await generatePdf(invoice);
      final text = formatReceiptText(invoice);
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'IRONBLOOD_Receipt_${invoice.invoiceNo}.pdf',
        subject:
            "IRONBLOOD Gym Invoice #${invoice.invoiceNo} - ${invoice.memberName}",
        body: text,
      );
    } catch (e) {
      debugPrint("sharePdfFile error: $e");
    }
  }

  /// Show Modern Luxury Receipt Modal in Flutter UI with In-App Actions
  static void showReceiptDialog({
    required BuildContext context,
    required InvoiceModel invoice,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFC9A227), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Gym Brand Logo Badge with Dark BG, Square Shape & Gold Border
                  Container(
                    width: 68,
                    height: 68,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07120A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFC9A227),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFC9A227,
                          ).withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'lib/logo.png',
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          errorBuilder: (ctx, err, stack) => Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF059669), Color(0xFF10B981)],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.fitness_center_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    "IRONBLOOD FITNESS",
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                      color: const Color(0xFFC9A227),
                    ),
                  ),
                  Text(
                    "OFFICIAL INVOICE",
                    style: GoogleFonts.rajdhani(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: const Color(0xFFFFE082),
                    ),
                  ),
                  Text(
                    "Receipt #${invoice.invoiceNo}",
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Receipt Summary Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06140D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E4230)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildReceiptRow(
                          "Athlete",
                          "${invoice.memberName} (${invoice.memberId})",
                        ),
                        const SizedBox(height: 6),
                        _buildReceiptRow(
                          "Date",
                          _formatDate(invoice.invoiceDate),
                        ),
                        const SizedBox(height: 6),
                        _buildReceiptRow(
                          "Payment Mode",
                          invoice.paymentMode,
                          valueColor: const Color(0xFFFFE082),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(color: Color(0xFF1B4931), height: 1),
                        ),
                        if (invoice.items.length > 1) ...[
                          Text(
                            "ITEMIZED SERVICES",
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: const Color(0xFFC9A227),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...invoice.items.asMap().entries.map((entry) {
                            final idx = entry.key + 1;
                            final it = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B2117),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF1E4230),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "$idx. ${it.description}",
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (it.coachOrDetails != null &&
                                            it.coachOrDetails!.isNotEmpty)
                                          Text(
                                            it.coachOrDetails!,
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF10B981),
                                            ),
                                          ),
                                        if (it.startDate != null &&
                                            it.expiryDate != null)
                                          Text(
                                            "${_formatDate(it.startDate!)} - ${_formatDate(it.expiryDate!)}",
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white54,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _formatCurrency(it.amount),
                                    style: GoogleFonts.montserrat(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFFFE082),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 4),
                        ] else ...[
                          _buildReceiptRow("Plan Subscribed", invoice.planName),
                          if (invoice.trainerName != null &&
                              invoice.trainerName!.isNotEmpty &&
                              invoice.trainerName != 'Unassigned') ...[
                            const SizedBox(height: 6),
                            _buildReceiptRow("PT Coach", invoice.trainerName!),
                          ],
                          const SizedBox(height: 6),
                          _buildReceiptRow(
                            "Validity",
                            "${_formatDate(invoice.startDate)} - ${_formatDate(invoice.expiryDate)}",
                          ),
                        ],
                        if (invoice.discountAmount > 0) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Divider(color: Color(0xFF1B4931), height: 1),
                          ),
                          _buildReceiptRow(
                            "Gross Subtotal",
                            _formatCurrency(invoice.basePrice),
                          ),
                          const SizedBox(height: 4),
                          _buildReceiptRow(
                            "Discount Applied",
                            "- ${_formatCurrency(invoice.discountAmount)}",
                            valueColor: const Color(0xFF81C784),
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(color: Color(0xFF1B4931), height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "TOTAL PAID",
                              style: GoogleFonts.rajdhani(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: const Color(0xFFFFE082),
                              ),
                            ),
                            Text(
                              _formatCurrency(invoice.finalAmount),
                              style: GoogleFonts.montserrat(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFC9A227),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Side-by-side Action Buttons: VIEW INVOICE and DOWNLOAD
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.visibility_rounded,
                          label: "VIEW INVOICE",
                          backgroundColor: const Color(0xFFC9A227),
                          textColor: const Color(0xFF091911),
                          onTap: () {
                            Navigator.pop(context);
                            openPdfViewer(context, invoice);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.download_rounded,
                          label: "DOWNLOAD",
                          backgroundColor: const Color(0xFF103A27),
                          borderColor: const Color(0xFF236E4A),
                          textColor: const Color(0xFFFFE082),
                          onTap: () => downloadPdf(invoice),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Close / Done Button
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFF1E4230),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        "CLOSE",
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildReceiptRow(
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white60,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: valueColor ?? Colors.white,
          ),
        ),
      ],
    );
  }

  static Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color textColor,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
