// VERSÃO: v30
//
// Teste básico de integridade do ponto de entrada do aplicativo.
// Mantém a validação sem iniciar serviços externos, como Supabase.

import 'package:flutter_test/flutter_test.dart';
import 'package:universidade_lideres_app/main.dart';

void main() {
  test('cria a raiz da Universidade de Líderes', () {
    const app = UniversidadeLideresApp();

    expect(app, isA<UniversidadeLideresApp>());
  });
}
