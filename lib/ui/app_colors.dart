import 'package:flutter/material.dart';

/// Design tokens from the GAMMA web UI (`web/dist/style.css` :root).
/// Keep these in sync with the web values; use them instead of ad-hoc colors.
abstract final class AppColors {
  // Text
  static const text = Color(0xFF171B23);
  static const textDim = Color(0xFF5F6877);
  static const textFaint = Color(0xFF858D9B);

  // Surfaces
  static const surface = Colors.white;
  static const surfaceRaised = Color(0xFFF3F5F8);
  static const surfaceSoft = Color(0xFFF1F3F6);
  static const bg = Color(0xFFF7F8FA);
  static const bgDeep = Color(0xFFEEF1F5);

  // Lines
  static const border = Color(0x1A14202D);
  static const borderStrong = Color(0x2E14202D);

  // Accent
  static const accent = Color(0xFF4665C9);
  static const accentStrong = Color(0xFF2F4FAE);
  // Accent tints (web rgba(70,101,201, a))
  static const accentTint = Color(0x144665C9);
  static const accentTintActive = Color(0x664665C9);
  static const accentTintStrong = Color(0x334665C9);
  static const accentTintHover = Color(0x1F4665C9);

  // Gamma Indigo (mockup primary #4F46E5)
  static const gammaIndigo = Color(0xFF4F46E5);
  static const gammaIndigoLight = Color(0xFFEEF2FF);

  // Status mapping per spec: Encendido/Apagado/Desconectado + toast
  static const statusEncendido = Color(0xFF10B981);
  static const statusApagado = Color(0xFFEF4444);
  static const statusDesconectado = Color(0xFF9CA3AF);
  static const toastDark = Color(0xFF1F2937);
  // Aliases for design interface
  static const success = Color(0xFF10B981);
  static const errorRed = Color(0xFFEF4444);
  static const greyDesconectado = Color(0xFF9CA3AF);

  // Kind icon badge tints
  static const kindLight = Color(0xFF8B5CF6);
  static const kindBlinds = Color(0xFF06B6D4);
  static const kindFan = Color(0xFF34D399);
  static const kindSensorGrey = Color(0xFF9CA3AF);

  // Status
  static const green = Color(0xFF238457);
  static const red = Color(0xFFC94D5A);
  static const amber = Color(0xFF946914);

  // Orb halo/ring blue (web uses rgba(79,111,218,…))
  static const orbBlue = Color(0xFF4F6FDA);

  // Shadows (web: rgba(20,29,45,0.05) etc.)
  static const shadow = Color(0x0D14202D);
  static const shadowStrong = Color(0x0F14202D);
}
