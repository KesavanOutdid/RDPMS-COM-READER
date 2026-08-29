# RDPMS — Firmware Upload Protocol Specification

**Document Version:** 1.0  
**Date:** 08-May-2026  
**Status:** 🟡 AWAITING CONFIRMATION  
**Prepared by:** Software Team  
**To:** Hardware / Embedded Team

---

## 1. Purpose

This document defines the firmware upload protocol between the **RDPMS Serial Monitor** (Windows Desktop App) and the **target hardware device** over a serial (COM) port. The goal is to confirm this protocol specification before software implementation begins.

> [!IMPORTANT]
> Please review every section carefully and confirm or correct the details. Respond with **OK** or **corrections needed** for each section.

---

## 2. Protocol Overview

| Item | Value |
|---|---|
| Communication | Serial COM Port (USB) |
| Data format | All bytes sent as **HEX** format |
| Chunk size | **60 bytes** of data per frame |
| Frame size | **64 bytes** (2B serial + 60B data + 2B CRC) |
| Timeout | **30 seconds** per response |
| Expected response | **"OK"** from device |
| File type | `.bin` (binary firmware file) |

---

## 3. Upload Flow

```
Step 1:  User selects a .bin file
Step 2:  App calculates → file size, frame count, file CRC
Step 3:  App sends HEADER FRAME → waits for "OK" (30s)
Step 4:  App sends DATA FRAME 0 → waits for "OK" (30s)
Step 5:  App sends DATA FRAME 1 → waits for "OK" (30s)
  ...
Step N:  App sends last DATA FRAME → waits for "OK" (30s)
Step N+1: Upload Complete
```

---

## 4. Frame Definitions

### 4.1 Header Frame

Sent **once**, before any data frames.

| Byte Position | Field | Size | Description |
|---|---|---|---|
| Byte 0–3 | File Size | 4 bytes | Total size of the .bin file in bytes |
| Byte 4–5 | Frame Count | 2 bytes | Total number of data frames |
| Byte 6–7 | File CRC | 2 bytes | CRC-16 of the entire .bin file |
| | **Total** | **8 bytes** | |

### 4.2 Data Frame

Sent **repeatedly**, one per chunk, in order.

| Byte Position | Field | Size | Description |
|---|---|---|---|
| Byte 0–1 | Serial Number | 2 bytes | Frame index: 0x0000, 0x0001, 0x0002... |
| Byte 2–61 | Data | 60 bytes | Chunk of .bin file content |
| Byte 62–63 | Frame CRC | 2 bytes | CRC-16 of (Serial No + Data) = 62 bytes |
| | **Total** | **64 bytes** | |

---

## 5. Worked Example — 360-byte File

### 5.1 Input

```
File name:  firmware_v2.bin
File size:  360 bytes
```

### 5.2 Calculations

```
Chunk size   = 60 bytes
Frame count  = 360 ÷ 60 = 6 frames
File CRC-16  = 0xA3F1  (example value)
```

### 5.3 Header Frame

```
Byte:   [0]  [1]  [2]  [3]  [4]  [5]  [6]  [7]
Field:  ├── File Size ──┤  ├─ Count ─┤  ├─ CRC ──┤
Hex:     00   00   01   68   00   06   A3   F1

Sent over serial as: 00 00 01 68 00 06 A3 F1
```

> **Verification:** 0x00000168 = 360 decimal ✅ | 0x0006 = 6 frames ✅

### 5.4 Data Frames

| Frame | Serial No | Data Bytes | CRC | Total |
|---|---|---|---|---|
| Frame 0 | `00 00` | File byte 0 → 59 (60B) | 2B | 64B |
| Frame 1 | `00 01` | File byte 60 → 119 (60B) | 2B | 64B |
| Frame 2 | `00 02` | File byte 120 → 179 (60B) | 2B | 64B |
| Frame 3 | `00 03` | File byte 180 → 239 (60B) | 2B | 64B |
| Frame 4 | `00 04` | File byte 240 → 299 (60B) | 2B | 64B |
| Frame 5 | `00 05` | File byte 300 → 359 (60B) | 2B | 64B |

### 5.5 Full Transfer Timeline

```
TX → 00 00 01 68 00 06 A3 F1              (Header, 8 bytes)
RX ← OK                                    (within 30 seconds)

TX → 00 00 [60 bytes data] XX XX           (Frame 0, 64 bytes)
RX ← OK                                    (within 30 seconds)

TX → 00 01 [60 bytes data] XX XX           (Frame 1, 64 bytes)
RX ← OK                                    (within 30 seconds)

TX → 00 02 [60 bytes data] XX XX           (Frame 2, 64 bytes)
RX ← OK                                    (within 30 seconds)

TX → 00 03 [60 bytes data] XX XX           (Frame 3, 64 bytes)
RX ← OK                                    (within 30 seconds)

TX → 00 04 [60 bytes data] XX XX           (Frame 4, 64 bytes)
RX ← OK                                    (within 30 seconds)

TX → 00 05 [60 bytes data] XX XX           (Frame 5, 64 bytes)
RX ← OK                                    (within 30 seconds)

✅ UPLOAD COMPLETE
Total bytes sent: 8 + (6 × 64) = 392 bytes
```

---

## 6. Edge Case Example — 200-byte File

### 6.1 Calculations

```
File size    = 200 bytes
Frame count  = ceil(200 ÷ 60) = 4 frames  (3 full + 1 partial)
```

### 6.2 Data Frames

| Frame | Serial No | Data Source | Actual Data | Padding | CRC |
|---|---|---|---|---|---|
| Frame 0 | `00 00` | byte 0–59 | 60 bytes | 0 bytes | 2B |
| Frame 1 | `00 01` | byte 60–119 | 60 bytes | 0 bytes | 2B |
| Frame 2 | `00 02` | byte 120–179 | 60 bytes | 0 bytes | 2B |
| Frame 3 | `00 03` | byte 180–199 | 20 bytes | **40 bytes (0x00)** | 2B |

> **Last frame:** Only 20 real bytes + 40 zero-padded bytes = 60 bytes total in data field.  
> CRC is calculated on all 62 bytes (2B serial + 60B padded data).

---

## 7. Questions Requiring Confirmation

> [!WARNING]
> **Please provide answers to ALL items below before implementation starts.**

### Q1. CRC Algorithm

```
Which CRC-16 variant does the hardware expect?

□  CRC-16/MODBUS    (Poly: 0x8005, Init: 0xFFFF, Reflect: Yes)
□  CRC-16/CCITT     (Poly: 0x1021, Init: 0xFFFF, Reflect: No)
□  CRC-16/XMODEM    (Poly: 0x1021, Init: 0x0000, Reflect: No)
□  Other: _______________
```

### Q2. "OK" Response Format

```
What exact bytes does the device send as "OK"?

□  ASCII "OK"     → 2 bytes: 0x4F 0x4B
□  ASCII "OK\r\n" → 4 bytes: 0x4F 0x4B 0x0D 0x0A
□  Hex code       → specific bytes: _______________
□  Other: _______________
```

### Q3. Byte Order (Endianness)

```
For multi-byte fields (File Size, Frame Count, Serial No):

□  Big-Endian     (MSB first) → 360 = 00 00 01 68
□  Little-Endian  (LSB first) → 360 = 68 01 00 00
```

### Q4. Header Frame Prefix

```
Does the header need an identifier byte prefix?
(Similar to how CAN uses 0xA0, 0xF1, 0xD0)

□  No prefix — send raw 8 bytes directly
□  Yes, prefix byte: 0x___ (specify)
□  Other: _______________
```

### Q5. Last Frame Padding

```
When the last chunk has fewer than 60 bytes:

□  Zero-pad to 60 bytes (frame stays 64 bytes)
□  Send shorter frame (variable length)
```

### Q6. Error Response

```
If the device rejects a frame, what does it send?

□  No response (timeout only)
□  ASCII "FAIL" or "ERROR"
□  Specific hex code: _______________

What should the app do on error?
□  Retry the same frame (max ___ times)
□  Abort entire upload immediately
□  Retry entire upload from header
```

### Q7. Upload Trigger

```
Does the device need a special command BEFORE the header
to enter firmware upload mode?

□  No — just send the header directly
□  Yes — send command: _______________ and wait for: _______________
```

---

## 8. Summary Table

| # | Item | Proposed Value | Confirmed? |
|---|---|---|---|
| 1 | Chunk size | 60 bytes | ⬜ |
| 2 | Frame format | 2B serial + 60B data + 2B CRC = 64B | ⬜ |
| 3 | Header format | 4B size + 2B count + 2B CRC = 8B | ⬜ |
| 4 | Response | "OK" within 30 seconds | ⬜ |
| 5 | CRC variant | CRC-16/MODBUS | ⬜ |
| 6 | Byte order | Big-Endian | ⬜ |
| 7 | Last frame | Zero-padded to 60 bytes | ⬜ |
| 8 | All data as HEX | Yes | ⬜ |
| 9 | Error handling | Abort on timeout/error | ⬜ |
| 10 | Pre-upload command | None | ⬜ |

---

## 9. Sign-Off

| Role | Name | Date | Status |
|---|---|---|---|
| Software Team | | 08-May-2026 | ✅ Prepared |
| Hardware Team | | ___-___-2026 | ⬜ Pending Review |
| Project Lead | | ___-___-2026 | ⬜ Pending Approval |

---

*Please mark each checkbox in Section 7 and Section 8, then return this document to the software team to begin implementation.*
