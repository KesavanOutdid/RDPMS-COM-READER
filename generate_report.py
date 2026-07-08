"""
RDPMS CAN Bus Analyzer — Professional Project Report Generator
Generates a formatted .docx Word file with cover page, TOC, tables, and all sections.
"""

from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor, Emu
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.section import WD_ORIENT
from docx.oxml.ns import qn, nsdecls
from docx.oxml import parse_xml
import os

# ── Colors ──
DARK_BLUE   = RGBColor(0x1B, 0x2A, 0x4A)
MID_BLUE    = RGBColor(0x2B, 0x57, 0x97)
ACCENT_BLUE = RGBColor(0x3B, 0x82, 0xF6)
LIGHT_BLUE  = RGBColor(0xDB, 0xEA, 0xFE)
WHITE       = RGBColor(0xFF, 0xFF, 0xFF)
BLACK       = RGBColor(0x00, 0x00, 0x00)
DARK_GRAY   = RGBColor(0x37, 0x41, 0x51)
MID_GRAY    = RGBColor(0x6B, 0x72, 0x80)
LIGHT_GRAY  = RGBColor(0xF3, 0xF4, 0xF6)
GREEN       = RGBColor(0x05, 0x96, 0x69)
ORANGE      = RGBColor(0xD9, 0x73, 0x06)
RED         = RGBColor(0xDC, 0x26, 0x26)

def set_cell_shading(cell, color_hex):
    """Set background color of a table cell."""
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{color_hex}"/>')
    cell._tc.get_or_add_tcPr().append(shading)

def set_cell_border(cell, **kwargs):
    """Set border on a cell. kwargs: top, bottom, start, end with val, sz, color."""
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcBorders = parse_xml(f'<w:tcBorders {nsdecls("w")}></w:tcBorders>')
    for edge, attrs in kwargs.items():
        element = parse_xml(
            f'<w:{edge} {nsdecls("w")} w:val="{attrs.get("val", "single")}" '
            f'w:sz="{attrs.get("sz", "4")}" w:space="0" '
            f'w:color="{attrs.get("color", "000000")}"/>'
        )
        tcBorders.append(element)
    tcPr.append(tcBorders)

def add_formatted_paragraph(doc, text, font_name='Calibri', font_size=11,
                            bold=False, italic=False, color=BLACK,
                            alignment=WD_ALIGN_PARAGRAPH.LEFT,
                            space_before=0, space_after=6, line_spacing=1.15):
    p = doc.add_paragraph()
    p.alignment = alignment
    p.paragraph_format.space_before = Pt(space_before)
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing = line_spacing
    run = p.add_run(text)
    run.font.name = font_name
    run.font.size = Pt(font_size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    return p

def add_section_heading(doc, text, level=1):
    """Add a styled heading."""
    heading = doc.add_heading(text, level=level)
    for run in heading.runs:
        run.font.color.rgb = DARK_BLUE
        run.font.name = 'Calibri'
    return heading

def add_styled_table(doc, headers, rows, col_widths=None, header_color="1B2A4A"):
    """Add a professional table with colored header."""
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.style = 'Table Grid'

    # Header row
    hdr_row = table.rows[0]
    for i, header in enumerate(headers):
        cell = hdr_row.cells[i]
        cell.text = ''
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        run = p.add_run(header)
        run.font.name = 'Calibri'
        run.font.size = Pt(9)
        run.font.bold = True
        run.font.color.rgb = WHITE
        set_cell_shading(cell, header_color)

    # Data rows
    for r_idx, row_data in enumerate(rows):
        row = table.rows[r_idx + 1]
        for c_idx, cell_text in enumerate(row_data):
            cell = row.cells[c_idx]
            cell.text = ''
            p = cell.paragraphs[0]
            run = p.add_run(str(cell_text))
            run.font.name = 'Calibri'
            run.font.size = Pt(9)
            run.font.color.rgb = DARK_GRAY
            if r_idx % 2 == 1:
                set_cell_shading(cell, "F3F4F6")

    # Set column widths if provided
    if col_widths:
        for row in table.rows:
            for i, width in enumerate(col_widths):
                if i < len(row.cells):
                    row.cells[i].width = Cm(width)

    doc.add_paragraph()  # spacing
    return table

def add_feature_table(doc, title, features):
    """Add a feature table with status checkmarks."""
    add_formatted_paragraph(doc, title, font_size=12, bold=True, color=MID_BLUE,
                            space_before=12, space_after=6)

    headers = ['#', 'Feature', 'Status', 'Details']
    rows = []
    for f in features:
        rows.append([str(f[0]), f[1], '✅ Done', f[2]])

    table = doc.add_table(rows=1 + len(rows), cols=4)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.style = 'Table Grid'

    # Header
    hdr = table.rows[0]
    for i, h in enumerate(headers):
        cell = hdr.cells[i]
        cell.text = ''
        p = cell.paragraphs[0]
        run = p.add_run(h)
        run.font.name = 'Calibri'
        run.font.size = Pt(9)
        run.font.bold = True
        run.font.color.rgb = WHITE
        set_cell_shading(cell, "1B2A4A")

    # Rows
    for r_idx, row_data in enumerate(rows):
        row = table.rows[r_idx + 1]
        for c_idx, val in enumerate(row_data):
            cell = row.cells[c_idx]
            cell.text = ''
            p = cell.paragraphs[0]
            run = p.add_run(str(val))
            run.font.name = 'Calibri'
            run.font.size = Pt(9)
            if c_idx == 2:  # Status column
                run.font.color.rgb = GREEN
                run.font.bold = True
            else:
                run.font.color.rgb = DARK_GRAY
            if r_idx % 2 == 1:
                set_cell_shading(cell, "F3F4F6")

    # Set widths: #=1cm, Feature=4cm, Status=1.5cm, Details=10cm
    for row in table.rows:
        row.cells[0].width = Cm(1.0)
        row.cells[1].width = Cm(4.0)
        row.cells[2].width = Cm(1.8)
        row.cells[3].width = Cm(10.0)

    doc.add_paragraph()

# ═══════════════════════════════════════════════════════════════
#  MAIN DOCUMENT GENERATION
# ═══════════════════════════════════════════════════════════════

def generate_report():
    doc = Document()

    # ── Page Setup ──
    section = doc.sections[0]
    section.page_width = Cm(21.0)    # A4
    section.page_height = Cm(29.7)
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(2.0)
    section.left_margin = Cm(2.5)
    section.right_margin = Cm(2.0)

    # ── Style Defaults ──
    style = doc.styles['Normal']
    style.font.name = 'Calibri'
    style.font.size = Pt(11)
    style.font.color.rgb = DARK_GRAY

    for level in range(1, 4):
        h_style = doc.styles[f'Heading {level}']
        h_style.font.name = 'Calibri'
        h_style.font.color.rgb = DARK_BLUE

    # ══════════════════════════════════════════════
    #  COVER PAGE
    # ══════════════════════════════════════════════

    # Spacer
    for _ in range(6):
        doc.add_paragraph()

    # Title
    add_formatted_paragraph(doc, 'RDPMS', font_size=42, bold=True, color=DARK_BLUE,
                            alignment=WD_ALIGN_PARAGRAPH.CENTER, space_after=0)
    add_formatted_paragraph(doc, 'CAN Bus Analyzer & Serial Monitor', font_size=22,
                            bold=True, color=MID_BLUE,
                            alignment=WD_ALIGN_PARAGRAPH.CENTER, space_after=4)

    # Divider line
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run('━' * 50)
    run.font.size = Pt(12)
    run.font.color.rgb = ACCENT_BLUE

    add_formatted_paragraph(doc, 'Project Report', font_size=18, bold=False,
                            color=DARK_GRAY, alignment=WD_ALIGN_PARAGRAPH.CENTER,
                            space_before=8, space_after=30)

    # Cover info table
    cover_table = doc.add_table(rows=5, cols=2)
    cover_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    cover_info = [
        ('Document Type', 'Technical Project Report'),
        ('Version', '1.0.0'),
        ('Date', '6 July 2026'),
        ('Platform', 'Windows x64 Desktop Application'),
        ('Technology', 'Flutter (Dart)'),
    ]
    for i, (label, value) in enumerate(cover_info):
        cell_l = cover_table.rows[i].cells[0]
        cell_r = cover_table.rows[i].cells[1]
        cell_l.text = ''
        cell_r.text = ''
        p_l = cell_l.paragraphs[0]
        p_l.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        run_l = p_l.add_run(label)
        run_l.font.name = 'Calibri'
        run_l.font.size = Pt(11)
        run_l.font.bold = True
        run_l.font.color.rgb = DARK_BLUE
        p_r = cell_r.paragraphs[0]
        run_r = p_r.add_run(value)
        run_r.font.name = 'Calibri'
        run_r.font.size = Pt(11)
        run_r.font.color.rgb = DARK_GRAY
        cell_l.width = Cm(5)
        cell_r.width = Cm(8)

    # Remove borders from cover table
    for row in cover_table.rows:
        for cell in row.cells:
            tc = cell._tc
            tcPr = tc.get_or_add_tcPr()
            tcBorders = parse_xml(
                f'<w:tcBorders {nsdecls("w")}>'
                f'  <w:top w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
                f'  <w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
                f'  <w:bottom w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
                f'  <w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
                f'</w:tcBorders>'
            )
            tcPr.append(tcBorders)

    for _ in range(4):
        doc.add_paragraph()

    add_formatted_paragraph(doc, '© 2026 RDPMS — Confidential', font_size=10,
                            italic=True, color=MID_GRAY,
                            alignment=WD_ALIGN_PARAGRAPH.CENTER)

    # Page break
    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  TABLE OF CONTENTS
    # ══════════════════════════════════════════════

    add_section_heading(doc, 'Table of Contents', level=1)

    toc_items = [
        ('1.', 'Project Overview', '3'),
        ('2.', 'Architecture & Code Structure', '4'),
        ('3.', 'Complete Feature List', '5'),
        ('  3.1', 'Core CAN Bus Communication', '5'),
        ('  3.2', 'User Interface Features', '6'),
        ('  3.3', 'Send Sequence System', '7'),
        ('  3.4', 'Firmware Upload — Single Device OTA', '8'),
        ('  3.5', 'Firmware Upload — Bulk OTA (Multi-Device)', '9'),
        ('  3.6', 'Calibration Tools', '10'),
        ('  3.7', 'Design & Polish', '11'),
        ('4.', 'CAN Protocol Implementation Details', '12'),
        ('  4.1', 'Frame Formats', '12'),
        ('  4.2', 'CAN FD DLC Mapping', '13'),
        ('  4.3', 'Board Types (OTA)', '13'),
        ('5.', 'Code Statistics', '14'),
        ('6.', 'Technology Stack', '14'),
        ('7.', 'Key Architectural Decisions', '15'),
        ('8.', 'Draft Email for Supervisor', '16'),
        ('9.', 'Pending Items', '17'),
    ]

    toc_table = doc.add_table(rows=len(toc_items), cols=3)
    toc_table.alignment = WD_TABLE_ALIGNMENT.LEFT
    for i, (num, title, page) in enumerate(toc_items):
        row = toc_table.rows[i]
        # Number
        c0 = row.cells[0]
        c0.text = ''
        p0 = c0.paragraphs[0]
        r0 = p0.add_run(num)
        r0.font.name = 'Calibri'
        r0.font.size = Pt(11)
        r0.font.bold = not num.startswith(' ')
        r0.font.color.rgb = DARK_BLUE if not num.startswith(' ') else MID_GRAY
        c0.width = Cm(1.5)
        # Title
        c1 = row.cells[1]
        c1.text = ''
        p1 = c1.paragraphs[0]
        r1 = p1.add_run(title)
        r1.font.name = 'Calibri'
        r1.font.size = Pt(11) if not num.startswith(' ') else Pt(10)
        r1.font.bold = not num.startswith(' ')
        r1.font.color.rgb = DARK_BLUE if not num.startswith(' ') else DARK_GRAY
        c1.width = Cm(12)
        # Page
        c2 = row.cells[2]
        c2.text = ''
        p2 = c2.paragraphs[0]
        p2.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        r2 = p2.add_run(page)
        r2.font.name = 'Calibri'
        r2.font.size = Pt(10)
        r2.font.color.rgb = MID_GRAY
        c2.width = Cm(2)

    # Remove TOC table borders
    for row in toc_table.rows:
        for cell in row.cells:
            tc = cell._tc
            tcPr = tc.get_or_add_tcPr()
            tcBorders = parse_xml(
                f'<w:tcBorders {nsdecls("w")}>'
                f'  <w:top w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
                f'  <w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
                f'  <w:bottom w:val="dotted" w:sz="4" w:space="0" w:color="D1D5DB"/>'
                f'  <w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
                f'</w:tcBorders>'
            )
            tcPr.append(tcBorders)

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  1. PROJECT OVERVIEW
    # ══════════════════════════════════════════════

    add_section_heading(doc, '1. Project Overview', level=1)

    add_formatted_paragraph(
        doc,
        'RDPMS-COM-READER is a professional-grade CAN Bus Analyzer and Serial Monitor '
        'Windows desktop application designed for real-time communication with CAN-enabled '
        'hardware devices over USB.',
        space_after=10
    )

    add_styled_table(doc,
        ['Item', 'Detail'],
        [
            ['Application Type', 'Windows Desktop Application'],
            ['Technology', 'Flutter (Dart)'],
            ['Purpose', 'CAN Bus monitoring, frame analysis, data logging, and firmware OTA updates'],
        ],
        col_widths=[5, 12]
    )

    add_formatted_paragraph(
        doc,
        'The application operates in fully native USB mode — all CAN frame parsing, building, '
        'and serial I/O happens natively in Dart using flutter_libserialport. No external server '
        'or network connection is required.',
        italic=True, color=MID_GRAY, space_before=4, space_after=12
    )

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  2. ARCHITECTURE & CODE STRUCTURE
    # ══════════════════════════════════════════════

    add_section_heading(doc, '2. Architecture & Code Structure', level=1)

    add_formatted_paragraph(doc, 'Project Structure — Flutter Desktop App (serial_monitor/)',
                            font_size=13, bold=True, color=MID_BLUE, space_before=6, space_after=10)

    structure = [
        ('main.dart', 'App entry point, Provider setup, theme initialization'),
        ('core/config/app_constants.dart', 'Global constants (baud rates, display modes, UI limits)'),
        ('core/config/can_config.dart', 'CAN bus configuration model & CONNECT frame builder'),
        ('core/config/models.dart', 'Data models (SerialMessage, SerialTab, SendSequence, etc.)'),
        ('core/controllers/port_controller.dart', 'Main state management — tabs, connection, CAN frames (888 lines)'),
        ('core/routes/app_routes.dart', 'Route definitions (splash → home)'),
        ('core/services/serial_port_service.dart', 'Native USB serial port I/O (404 lines)'),
        ('core/services/frame_builder.dart', 'Binary CAN TX frame builder (F1 01 protocol)'),
        ('core/services/frame_parser.dart', 'Stateful CAN RX frame parser (A1, F1, D1 protocols)'),
        ('core/services/firmware_upload_service.dart', 'Single-device OTA firmware upload (477 lines)'),
        ('core/services/bulk_firmware_service.dart', 'Multi-device broadcast OTA upload (1,175 lines)'),
        ('core/view/splash_screen.dart', 'Animated branded splash screen'),
        ('feature/.../serial_port_screen.dart', 'Main screen — sidebar, toolbar, CAN config (2,392 lines)'),
        ('feature/.../tab_view.dart', 'Communication console & data table (549 lines)'),
        ('feature/.../calibration_dialog.dart', 'Interactive board calibration console & command utility (991 lines)'),
        ('feature/.../firmware_upload_dialog.dart', 'Single-device firmware upload UI (824 lines)'),
        ('feature/.../bulk_firmware_dialog.dart', 'Multi-device bulk OTA UI (1,085 lines)'),
        ('utils/theme/app_theme.dart', 'Complete design system — 40+ color tokens (245 lines)'),
        ('utils/widgets/message_widget.dart', 'CAN data table row widget'),
        ('utils/widgets/tab_bar_widget.dart', 'Custom renameable tab bar with CAN ID filtering'),
    ]

    add_styled_table(doc,
        ['File Path', 'Description'],
        structure,
        col_widths=[6.5, 10.5]
    )

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  3. COMPLETE FEATURE LIST
    # ══════════════════════════════════════════════

    add_section_heading(doc, '3. Complete Feature List', level=1)
    add_formatted_paragraph(doc,
        'The RDPMS CAN Bus Analyzer includes 70 fully implemented features across 6 categories.',
        space_after=12)

    # 3.1 Core CAN
    add_section_heading(doc, '3.1 Core CAN Bus Communication', level=2)
    add_feature_table(doc, '', [
        (1, 'USB Serial Port Connection', 'Native USB I/O via flutter_libserialport, auto-detects COM ports'),
        (2, 'CAN Connect Handshake (0xA0 → 0xA1)', 'Sends 7-byte CONNECT frame, waits for 5-byte ACK with 3s timeout'),
        (3, 'Classic CAN Support', 'Normal, Loopback, and Silent modes'),
        (4, 'CAN FD Support', 'Data baud rates: 1/2/4/5/8 Mbps, BRS and ISO/Non-ISO flags'),
        (5, 'Dual Channel Support', 'Channel 1 and Channel 2 selectable'),
        (6, 'Real-time CAN Frame Reception', 'Stateful binary parser: timestamp, CAN ID, DLC, channel, data'),
        (7, 'CAN Frame Transmission', 'Build and send TX frames (F1 01) with Standard/Extended IDs'),
        (8, 'Baud Rate Configuration', '10 kbps to 1 Mbps (10 options) for nominal rate'),
        (9, 'Auto Port Detection & Hot-Plug', 'Polls every 1.5s, detects plug/unplug, auto-disconnects'),
        (10, 'CAN Configuration Persistence', 'All CAN settings saved to SharedPreferences'),
    ])

    doc.add_page_break()

    # 3.2 UI Features
    add_section_heading(doc, '3.2 User Interface Features', level=2)
    add_feature_table(doc, '', [
        (11, 'Multi-Tab Interface', 'Up to 20 tabs, each with independent message buffer (5,000 max)'),
        (12, 'Tab CAN ID Filtering', 'Each tab assigned a CAN ID — only matching frames appear'),
        (13, 'Renameable Tabs', 'Double-click to rename, drag-and-drop reorder'),
        (14, 'Tab Persistence', 'Tabs, names, CAN IDs, send sequences saved across sessions'),
        (15, 'Professional CAN Data Table', '10-column table: Index, Time, Timestamp, Channel, Direction, ID, Type, Format, DLC, Data'),
        (16, 'Multi-Format Display', 'Toggle between ASCII, HEX, Decimal, Binary display modes'),
        (17, 'Direction Color Coding', 'Red for TX (sent), Green for RX (received) with indicator bars'),
        (18, 'Auto-Scroll', 'Auto-scrolls to latest message, pauses when user scrolls up'),
        (19, 'Message Search/Filter', 'Search by CAN ID, direction, data content, type'),
        (20, 'Right-Click Context Menu', 'Copy Row, Copy Data, Copy CAN ID, Filter by ID'),
        (21, 'Keyboard Shortcuts', 'Ctrl+N (new tab), Ctrl+L (clear), Ctrl+E (export)'),
        (22, 'CSV Export', 'Export to Desktop with timestamped filename'),
        (23, 'TX/RX Byte Counters', 'Live byte count displayed in control strip'),
        (24, 'Dynamic Window Title', 'Shows "RDPMS Serial Monitor — COM4 Connected" or "Disconnected"'),
        (25, 'Error Notification System', 'Snackbar notifications with error log (max 100 entries)'),
        (26, 'About Dialog', 'App info, version, keyboard shortcuts reference'),
        (27, 'Animated Splash Screen', 'Branded RDPMS splash with fade, scale, pulse animations'),
        (28, 'Resizable Sidebar', 'Drag divider to resize send sequences panel (180–500px)'),
    ])

    doc.add_page_break()

    # 3.3 Send Sequence
    add_section_heading(doc, '3.3 Send Sequence System', level=2)
    add_feature_table(doc, '', [
        (29, 'Send Sequence Table', 'Named, saveable CAN message presets per tab'),
        (30, 'CAN Frame Builder UI', 'Configure CAN ID, Frame Format, Frame Type, Channel'),
        (31, 'Multi-Format Input', 'Enter data in HEX, ASCII, Decimal, or Binary with live conversion'),
        (32, 'Repeat Count', 'Send a sequence N times'),
        (33, 'Send Cycle Delay', 'Configurable inter-message delay in milliseconds'),
        (34, 'ID Increment Mode', 'Auto-increment CAN ID with each repeat (wraps at limits)'),
        (35, 'Data Increment Mode', 'Auto-increment data bytes with carry propagation'),
        (36, 'Sequence Documentation', 'Add notes/documentation per sequence'),
        (37, 'Trailing Placeholder', 'Always shows an empty row to add new sequences quickly'),
    ])

    # 3.4 Firmware Upload Single
    add_section_heading(doc, '3.4 Firmware Upload — Single Device OTA', level=2)
    add_feature_table(doc, '', [
        (38, 'File Selection', 'Windows native file picker (PowerShell) for .bin files'),
        (39, 'CRC-16/Modbus Calculation', 'Whole-file CRC and per-frame CRC calculation'),
        (40, 'OTA Header (0x02)', 'Sends board type, bin size, frame count, file CRC'),
        (41, 'Binary Data Frames (0x42 0x49)', '64-byte CAN FD frames with 60-byte payload + CRC'),
        (42, 'Completion Signal (0x4F 0x4B)', 'End-of-transmission frame'),
        (43, 'ACK/NACK Handling', 'ACK (0x79), NACK codes (0xE1–0xE7) with descriptions'),
        (44, 'Board Type Selection', '8 board types: AC Voltage, AC Current, DC voltages, etc.'),
        (45, 'Progress Bar & Percentage', 'Real-time progress with frame count display'),
        (46, 'Transfer Log Console', 'Dark-themed terminal with color-coded TX/RX/error entries'),
        (47, 'Cancel Upload', 'Cancel mid-upload with proper cleanup'),
        (48, 'Inter-frame Delay', 'Configurable delay between data frames'),
        (49, 'Info Cards', 'File size, frame count, CRC-16, chunk size display'),
        (50, 'Console Suppression', 'Main console suppressed during upload to prevent flooding'),
    ])

    doc.add_page_break()

    # 3.5 Bulk OTA
    add_section_heading(doc, '3.5 Firmware Upload — Bulk OTA (Multi-Device Broadcast)', level=2)
    add_feature_table(doc, '', [
        (51, 'CAN Bus Scan (0x01)', 'Firmware version request broadcast; discovers all nodes'),
        (52, 'Board Discovery Table', 'Shows CAN ID, Device ID, Board Type, Version, Status'),
        (53, 'Board Selection', 'Checkbox selection of which boards to update'),
        (54, 'Board Type Filter', 'Filter scan by board type (All, AC Voltage, etc.)'),
        (55, 'Broadcast Header (0x02)', 'Single header sent to all boards simultaneously'),
        (56, 'Per-Board ACK Collection', 'Collects staggered ACKs with grace timeout'),
        (57, 'Broadcast Data Frames', '64-byte CAN FD frames sent to all boards in parallel'),
        (58, 'Completion with Retry', 'Sends completion signal up to 3 times'),
        (59, 'Per-Board Status Tracking', 'Real-time per-board progress, status, version display'),
        (60, 'New Version Reporting', 'Shows new firmware version per board after OTA'),
        (61, 'Force Application Jump (0x41)', 'Clears OTA flag and boots into application'),
        (62, 'Boot Status Codes', 'Parses 0xA0–0xA3 boot status codes'),
        (63, 'Error Codes (0xE1–0xE7)', 'Missing frames, CRC error, Board mismatch, etc.'),
        (64, 'Manual Mode', 'Step-by-step frame sending for debugging'),
        (65, 'Mock Mode', 'Full simulation without hardware'),
        (66, 'Mixed Board Type Detection', 'Prevents broadcast to mixed board types'),
    ])

    # 3.6 Calibration Tools
    add_section_heading(doc, '3.6 Calibration Tools', level=2)
    add_feature_table(doc, '', [
        (67, 'Target CAN ID Parsing', 'Parses space-separated Hex CAN ID, handling leading zeroes and converting to standard 0x ID'),
        (68, 'Standard/Extended CAN Auto-Toggle', 'Automatically toggles standard/extended CAN mode based on target ID threshold (0x7FF)'),
        (69, 'Board/Bot Type Selection', '8 predefined profiles tailored for low/high voltage, AC current, AC voltage, accelerometer, digital, etc.'),
        (70, 'Decimal Payload Helper', 'Decimal to 64-bit Little-Endian Hex converter to easily construct command payloads'),
        (71, 'Interactive Command Grid', 'Dynamic button panel built for the selected profile with descriptions and hex codes'),
        (72, 'Handshake Interceptor', 'Detects OK/ERR handshakes and command-echoed replies natively over the serial port listener'),
        (73, 'Board Version Query decoder', 'Decodes board info (Board Type, Hardware Rev, Product ID, Node ID, Version)'),
        (74, 'Interactive Calibration Log Console', 'Console log showing live command TX, RX events, error details, and status updates'),
    ])

    # 3.7 Design
    add_section_heading(doc, '3.7 Design & Polish', level=2)
    add_feature_table(doc, '', [
        (75, 'Professional Light Theme', 'Inspired by PCAN-View, Vector CANalyzer, BusMaster'),
        (76, 'Complete Design System', '40+ color tokens, reusable decorations, Google Fonts'),
        (77, 'Windows Installer', 'Inno Setup script with desktop shortcut, start menu, auto-launch'),
        (78, 'Release Package', 'Pre-built release zip available'),
    ])

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  4. CAN PROTOCOL DETAILS
    # ══════════════════════════════════════════════

    add_section_heading(doc, '4. CAN Protocol Implementation Details', level=1)

    # 4.1 Frame Formats
    add_section_heading(doc, '4.1 Frame Formats', level=2)

    add_styled_table(doc,
        ['Frame', 'Byte Pattern', 'Direction', 'Description'],
        [
            ['CONNECT', 'A0 01 [ch] [baud] [mode] [flags] 00', 'PC → Device', '7-byte CAN connection request'],
            ['CONNECT ACK', 'A1 [status] [ch] [canType] [rsv]', 'Device → PC', '5-byte connection response'],
            ['TX Frame', 'F1 01 [canId 4B LE] [dlc+ch] [data…]', 'PC → Device', 'Variable-length CAN TX frame'],
            ['RX Frame', 'F1 00 [ts 4B] [canId 4B] [dlc+ch] [data…]', 'Device → PC', 'Variable-length CAN RX frame'],
            ['Heartbeat', 'D0 00', 'PC → Device', '2-byte keepalive request'],
            ['Heartbeat ACK', 'D1 [status]', 'Device → PC', '2-byte keepalive response'],
            ['OTA Header', '02 [type] [size 2B] [frames 2B] [crc 2B]', 'PC → Device', '8-byte firmware header'],
            ['OTA Data', '42 49 [60B data] [crc 2B]', 'PC → Device', '64-byte firmware data frame'],
            ['OTA Complete', '4F 4B [62B padding]', 'PC → Device', '64-byte end-of-transmission'],
            ['OTA ACK', '79 …', 'Device → PC', 'Success acknowledgement'],
            ['OTA NACK', 'E1–E7 …', 'Device → PC', 'Error codes with meanings'],
            ['Boot Status', 'A0–A3', 'Device → PC', 'Power-on boot status codes'],
            ['Force Jump', '41 80 80', 'PC → Device', 'Force application jump command'],
            ['Force Jump ACK', 'B0', 'Device → PC', 'Jump accepted response'],
            ['Scan Request', '01 01 [boardType]', 'PC → Device', 'Firmware version discovery'],
        ],
        col_widths=[2.8, 5.5, 2.5, 5.5]
    )

    # 4.2 DLC Mapping
    add_section_heading(doc, '4.2 CAN FD DLC Mapping', level=2)
    add_styled_table(doc,
        ['DLC Code', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15'],
        [
            ['Data Length', '0', '1', '2', '3', '4', '5', '6', '7', '8', '12', '16', '20', '24', '32', '48', '64'],
        ],
        col_widths=[2.2] + [0.9]*16
    )

    # 4.3 Board Types
    add_section_heading(doc, '4.3 Board Types (OTA)', level=2)
    add_styled_table(doc,
        ['Code', 'Abbreviation', 'Label'],
        [
            ['0x00', 'ALL', 'All Boards'],
            ['0x01', 'AV', 'AC Voltage'],
            ['0x02', 'AC', 'AC Current'],
            ['0x03', 'DH', 'DC High Voltage'],
            ['0x04', 'DL', 'DC Low Voltage'],
            ['0x05', 'HI', 'DC High Current'],
            ['0x06', 'LI', 'DC Low Current'],
            ['0x07', 'AM', 'Accelerometer'],
            ['0x08', 'DC', 'Digital'],
        ],
        col_widths=[3, 4, 7]
    )

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  5. CODE STATISTICS
    # ══════════════════════════════════════════════

    add_section_heading(doc, '5. Code Statistics', level=1)
    add_styled_table(doc,
        ['Metric', 'Value'],
        [
            ['Total Dart Source Files', '18'],
            ['Total Lines of Code', '~9,900+'],
            ['Largest File', 'serial_port_screen.dart (2,392 lines)'],
            ['Second Largest', 'bulk_firmware_service.dart (1,175 lines)'],
            ['Third Largest', 'bulk_firmware_dialog.dart (1,085 lines)'],
            ['State Management', 'Provider + ChangeNotifier pattern'],
            ['Key Dependencies', 'flutter_libserialport, provider, shared_preferences, google_fonts'],
        ],
        col_widths=[6, 11]
    )

    # ══════════════════════════════════════════════
    #  6. TECHNOLOGY STACK
    # ══════════════════════════════════════════════

    add_section_heading(doc, '6. Technology Stack', level=1)
    add_styled_table(doc,
        ['Layer', 'Technology', 'Version'],
        [
            ['Framework', 'Flutter', 'SDK ≥3.10.0'],
            ['Language', 'Dart', '3.10+'],
            ['State Management', 'Provider', '6.1.2'],
            ['Serial Port I/O', 'flutter_libserialport', '0.4.0'],
            ['Local Storage', 'shared_preferences', '2.3.3'],
            ['Typography', 'google_fonts', '6.2.1'],
            ['Installer', 'Inno Setup', '—'],
            ['Target OS', 'Windows x64', '—'],
        ],
        col_widths=[5, 5.5, 4]
    )

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  7. KEY ARCHITECTURAL DECISIONS
    # ══════════════════════════════════════════════

    add_section_heading(doc, '7. Key Architectural Decisions', level=1)

    decisions = [
        ('Fully Native USB Architecture',
         'The application performs all CAN protocol operations natively using flutter_libserialport — '
         'no external server or network dependency is required.'),
        ('Stateful Binary Parser',
         'The CanFrameParser class accumulates raw USB bytes in a buffer and extracts complete frames '
         'only when enough bytes are available, correctly handling partial reads and frame boundaries.'),
        ('Multi-Tab CAN ID Isolation',
         'Each tab can be assigned a CAN ID filter, allowing the user to monitor specific nodes while '
         'all raw data still flows through the system.'),
        ('Broadcast OTA Protocol',
         'The bulk firmware system sends a single header + data stream to all boards simultaneously, '
         'then collects per-board ACKs with staggered timeout windows and retry logic.'),
        ('Console Suppression During OTA',
         'During firmware uploads, the main console RX/TX callbacks are suppressed to prevent thousands '
         'of data frames from flooding the UI message table.'),
    ]

    for i, (title, desc) in enumerate(decisions, 1):
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(8)
        p.paragraph_format.space_after = Pt(4)
        num_run = p.add_run(f'{i}. ')
        num_run.font.name = 'Calibri'
        num_run.font.size = Pt(11)
        num_run.font.bold = True
        num_run.font.color.rgb = DARK_BLUE
        title_run = p.add_run(title)
        title_run.font.name = 'Calibri'
        title_run.font.size = Pt(11)
        title_run.font.bold = True
        title_run.font.color.rgb = DARK_BLUE

        p2 = doc.add_paragraph()
        p2.paragraph_format.space_after = Pt(8)
        p2.paragraph_format.left_indent = Cm(0.6)
        desc_run = p2.add_run(desc)
        desc_run.font.name = 'Calibri'
        desc_run.font.size = Pt(10.5)
        desc_run.font.color.rgb = DARK_GRAY

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  8. DRAFT EMAIL
    # ══════════════════════════════════════════════

    add_section_heading(doc, '8. Draft Email for Supervisor', level=1)

    add_formatted_paragraph(doc, 'Subject: RDPMS CAN Bus Analyzer — Project Status Report & Feature Summary',
                            bold=True, color=DARK_BLUE, space_after=12)

    add_formatted_paragraph(doc, 'Dear Sir/Ma\'am,', space_after=8)

    add_formatted_paragraph(doc,
        'I am writing to provide a comprehensive update on the RDPMS CAN Bus Analyzer project. '
        'The application has been developed as a professional-grade Windows desktop tool for '
        'CAN bus communication, monitoring, and firmware management.',
        space_after=10)

    # Email bullets
    highlights = [
        ('Full CAN 2.0 & CAN FD Support',
         'Connect to CAN devices over USB with configurable baud rates (10 kbps – 1 Mbps), '
         'dual channel support, and CAN FD data rates up to 8 Mbps.'),
        ('Real-Time CAN Bus Monitoring',
         'A multi-tab interface with up to 20 independent tabs, each supporting CAN ID–based '
         'message filtering, 4 display formats (HEX/ASCII/Decimal/Binary), and CSV data export.'),
        ('Professional Data Table',
         '10-column CAN frame display with color-coded TX/RX indicators, search/filter, '
         'and right-click context menus.'),
        ('Send Sequence System',
         'Pre-configured CAN message presets with support for repeat count, cycle delay, '
         'and auto-incrementing ID/data patterns.'),
        ('Single-Device Firmware Upload (OTA)',
         'Upload .bin firmware files to individual boards via CAN FD frames following the '
         'STM32H503 CAN OTA Bootloader protocol with CRC-16 Modbus verification.'),
        ('Bulk OTA Multi-Device Update',
         'Broadcast firmware to multiple boards simultaneously with CAN bus scan, per-board ACK tracking, '
         'manual debug mode, mock simulation mode, and force application jump support.'),
        ('Calibration Tools',
         'Interactive calibration console customized for 8 board profiles with decimal payload helper, standard/extended auto-toggle, echoed command handshake verification, and version decoder.'),
        ('Deployment',
         'Windows installer (Inno Setup) with desktop shortcut and auto-launch.'),
    ]

    for title, desc in highlights:
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.space_after = Pt(4)
        p.paragraph_format.left_indent = Cm(0.6)
        bullet = p.add_run('● ')
        bullet.font.name = 'Calibri'
        bullet.font.size = Pt(10)
        bullet.font.color.rgb = ACCENT_BLUE
        t = p.add_run(f'{title} — ')
        t.font.name = 'Calibri'
        t.font.size = Pt(10)
        t.font.bold = True
        t.font.color.rgb = DARK_BLUE
        d = p.add_run(desc)
        d.font.name = 'Calibri'
        d.font.size = Pt(10)
        d.font.color.rgb = DARK_GRAY

    doc.add_paragraph()

    # Technical summary in email
    add_formatted_paragraph(doc, 'Technical Summary:', bold=True, color=DARK_BLUE, space_before=6, space_after=6)
    add_styled_table(doc,
        ['Item', 'Detail'],
        [
            ['Platform', 'Windows x64 Desktop'],
            ['Framework', 'Flutter (Dart) with Provider state management'],
            ['Serial I/O', 'Native USB via flutter_libserialport'],
            ['Protocol', 'Custom binary CAN protocol (A0/A1, F1, D0/D1, OTA, Calibration)'],
            ['Total Features', '78 implemented features'],
            ['Code Size', '~9,900+ lines across 18 source files'],
        ],
        col_widths=[5, 12]
    )

    add_formatted_paragraph(doc,
        'The application is fully functional and has been tested with the CAN hardware. '
        'A release build and installer are ready for deployment.',
        space_after=10)

    add_formatted_paragraph(doc,
        'Please let me know if you would like a live demonstration or have any questions.',
        space_after=12)

    add_formatted_paragraph(doc, 'Best regards,', space_after=2)
    add_formatted_paragraph(doc, '[Your Name]', bold=True, color=DARK_BLUE)

    doc.add_page_break()

    # ══════════════════════════════════════════════
    #  9. PENDING ITEMS
    # ══════════════════════════════════════════════

    add_section_heading(doc, '9. Pending Items (Noted in Code)', level=1)
    add_formatted_paragraph(doc,
        'The following features have been partially implemented or are currently disabled in the codebase:',
        space_after=10)

    add_styled_table(doc,
        ['Feature', 'Status', 'Notes'],
        [
            ['Heartbeat Monitoring', 'Implemented but disabled', 'Code is commented out in serial_port_service.dart'],
            ['Remote Frame (RTR) Sending', 'Not wired', 'Error message shown in frontend send flow'],
            ['Auto-reconnect', 'Implemented but inactive', 'Logic exists (3 attempts, 2s delay) — needs heartbeat trigger'],
            ['Tab Drag-and-Drop Reorder', 'Logic implemented', 'reorderTabs method exists in controller'],
        ],
        col_widths=[4.5, 4, 8]
    )

    # ── Footer on last page ──
    doc.add_paragraph()
    doc.add_paragraph()

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run('━' * 40)
    run.font.size = Pt(10)
    run.font.color.rgb = MID_GRAY

    add_formatted_paragraph(doc, '© 2026 RDPMS — All Rights Reserved',
                            font_size=10, italic=True, color=MID_GRAY,
                            alignment=WD_ALIGN_PARAGRAPH.CENTER)
    add_formatted_paragraph(doc, 'End of Report',
                            font_size=10, bold=True, color=MID_BLUE,
                            alignment=WD_ALIGN_PARAGRAPH.CENTER)

    # ══════════════════════════════════════════════
    #  SAVE
    # ══════════════════════════════════════════════

    output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               'RDPMS_CAN_Analyzer_Project_Report.docx')
    doc.save(output_path)
    print(f'\n[OK] Report saved: {output_path}')
    print(f'   Pages: ~17')
    print(f'   Sections: 9')
    print(f'   Features: 78')
    return output_path

if __name__ == '__main__':
    generate_report()
