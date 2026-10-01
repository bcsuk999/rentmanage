import 'package:flutter/material.dart';

import 'api.dart';
import 'home_page.dart';
import 'login_page.dart';

void main() {
  runApp(const RentManageApp());
}

class RentManageApp extends StatefulWidget {
  const RentManageApp({super.key});

  @override
  State<RentManageApp> createState() => _RentManageAppState();
}

class _RentManageAppState extends State<RentManageApp> {
  final ApiClient _api = ApiClient(apiBaseUrl);
  Map<String, dynamic>? _user;

  @override
  Widget build(BuildContext context) {
    final signedIn = _user != null;
    return MaterialApp(
      title: 'Rent Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F5EFF)),
        useMaterial3: true,
      ),
      home: signedIn
          ? HomePage(
              api: _api,
              user: _user!,
              onSignOut: () => setState(() => _user = null),
            )
          : LoginPage(
              api: _api,
              onSignedIn: (user) => setState(() => _user = user),
            ),
    );
  }
}
