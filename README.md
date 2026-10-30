# Fluxo

App de iPhone para ver en un **calendario** todo lo que pagas: suscripciones, recibos y los movimientos de tu banco. Diseño con **Liquid Glass** y widgets para la pantalla de inicio y la de bloqueo.

## Descargar

Ve a **[Releases](../../releases/latest)** y descarga `Fluxo.ipa`. Instálala con **SideStore**.
Los widgets no funcionan dentro de LiveContainer.

Requiere iOS 26 o posterior.

## Conectar el banco (Enable Banking, gratis para tus propias cuentas)

1. Crea una cuenta en [enablebanking.com](https://enablebanking.com).
2. En *Aplicaciones API*, registra una app **Production** con la URL de redirección
   `https://arkellmusic.github.io/fluxo-ios/callback.html` y guarda el `.pem`.
3. Pulsa *Activate by linking accounts* y vincula tu banco.
4. En Fluxo, ve a *Ajustes › Conectar mi banco*, pega el Application ID, importa el `.pem` y elige tu banco.

La conexión es de solo lectura. La clave se guarda en el llavero del iPhone y los datos no salen del dispositivo, salvo hacia Enable Banking y tu banco.

## Compilación

Cada push a `main` compila la app en GitHub Actions (XcodeGen + Xcode, sin firmar) y publica la `.ipa` como release.
