import 'package:flutter/material.dart';

class AppColors {
  // Primary color used throughout the app
  // Accent color as defined by your theme
  static const Color themeAccent = Color(0xFF1CBCAC); // Your accent teal

  static const Color poofColor =Color.fromARGB(255, 151, 40, 181);

  static const Color lightPoofColor =Color.fromARGB(150, 151, 40, 181);

  //Old primary color static const Color primary = Colors.blue; // Change this to your desired color
  static const Color primary = poofColor; // Change this to your desired color

  // Secondary color (optional)
  static const Color secondary = Colors.grey;

  // Background color (optional)
  static const Color background = Colors.white;

  // Text colors (optional)
  static const Color primaryText = Colors.black;
  static const Color secondaryText = Colors.black;

  // Button colors (optional)
 // Old blue color static const Color buttonBackground = Color(0XFF57B9FF); // Matches WelcomeButton
  static const Color buttonBackground = poofColor; // Matches WelcomeButton
  
  static const Color buttonText = Colors.white;
}
