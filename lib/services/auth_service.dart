import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

class AuthService {
  // Base URL of the RP backend.
  static const backendUrl = 'http://localhost:3005';

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(backendUrl).replace(path: path, queryParameters: query);

  /// Asks for a ticket, opens the login in a new tab and polls until it completes.
  ///
  /// IMPORTANT: the tab is opened FIRST, before any `await`. Browsers only allow
  /// `window.open` during the user's click; after an `await` it may be blocked.
  Future<String> iniciarSesion() async {
    final tab = web.window.open('', '_blank');
    if (tab == null) {
      throw Exception('El navegador bloqueó la ventana. Permite las ventanas emergentes para este sitio.');
    }

    try {
      final inicioRes = await http.post(_uri('/api/login/start'));
      if (inicioRes.statusCode != 200) {
        throw Exception('Error al iniciar el login (${inicioRes.statusCode})');
      }

      final inicio = jsonDecode(inicioRes.body) as Map<String, dynamic>;
      final ticket = inicio['ticket'] as String;
      final secreto = inicio['poll_secret'] as String;

      // Point the already-open tab to the login address.
      tab.location.href = inicio['login_url'] as String;

      final intervalo = Duration(seconds: inicio['interval'] as int);
      final limite =
          DateTime.now().add(Duration(seconds: inicio['expires_in'] as int));

      while (DateTime.now().isBefore(limite)) {
        await Future.delayed(intervalo);

        final r = await http.get(
          _uri('/api/login/status', {'ticket': ticket}),
          headers: {'X-Poll-Secret': secreto},
        );

        if (r.statusCode != 200) {
          throw Exception(
              'Sondeo de inicio de sesión no válido o caducado (${r.statusCode})');
        }

        final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
        switch (cuerpo['status']) {
          case 'complete':
            return cuerpo['app_token'] as String;
          case 'error':
            throw Exception('El inicio de sesión falló en el proveedor.');
        }
      }
      throw Exception('El tiempo de espera del inicio de sesión caducó.');
    } catch (_) {
      // Do not leave an empty tab behind if something failed.
      if (!tab.closed) tab.close();
      rethrow;
    }
  }

  /// Reads the profile of the signed-in user with the app_token.
  Future<dynamic> leerPerfil(String token) async {
    final r = await http.get(
      _uri('/api/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (r.statusCode == 401) return null; // Session expired
    if (r.statusCode != 200) {
      throw Exception('Error al obtener el perfil (${r.statusCode})');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Ends the session in the backend.
  Future<void> cerrarSesion(String token) async {
    await http.post(
      _uri('/api/logout'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}