<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Icono de stepbro whispr">
</p>

<h1 align="center">stepbro whispr</h1>

<p align="center">
  Dictado por voz para macOS. Mantén una tecla, habla y el texto aparece limpio donde estés escribiendo.
</p>

<p align="center">
  <a href="https://github.com/kevin9038440334/stepbro-whispr/releases/latest"><img src="https://img.shields.io/github/v/release/kevin9038440334/stepbro-whispr?label=versi%C3%B3n&color=1f1f22" alt="Última versión"></a>
  <img src="https://img.shields.io/badge/macOS-27%2B-1f1f22?logo=apple" alt="macOS 27 o posterior">
  <img src="https://img.shields.io/badge/Swift-6.4-1f1f22?logo=swift" alt="Swift 6.4">
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/licencia-PolyForm%20Noncommercial-1f1f22" alt="Licencia: PolyForm Noncommercial 1.0.0"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>Español</strong>
</p>

---

stepbro whispr es una app nativa de macOS escrita en Swift y SwiftUI, con interfaz Liquid Glass. Es una alternativa gratuita a herramientas de dictado de pago como Wispr Flow: funciona en cualquier app, respeta tus palabras y se encarga de la puntuación, las listas y las rectificaciones.

Puede funcionar entera en tu Mac, con el reconocimiento de voz de Apple y Apple Intelligence, o con tu propia clave de Groq para usar Whisper y modelos de lenguaje más grandes en la nube.

## Funciones

- **Dicta en cualquier sitio.** Mantén la tecla (Fn por defecto), habla y suelta. El texto se pega donde está el cursor y el portapapeles vuelve a como estaba.
- **Manos libres.** Doble toque a la tecla para grabar sin mantenerla; otro toque para terminar. Esc cancela en cualquier momento.
- **Tus palabras, limpias.** Quita muletillas y repeticiones, aplica rectificaciones («a las cinco, no, a las seis» queda en «a las seis») y corrige por el contexto las palabras mal oídas, sin parafrasear.
- **Formato.** Preguntas y exclamaciones con ¿? y ¡!, listas numeradas y con viñetas, puntuación dictada («coma», «nuevo párrafo»), correos y enlaces.
- **Diccionario y atajos.** Nombres y términos que siempre se escriben bien, y frases cortas que se convierten en un texto más largo.
- **Estilo por app.** Casual en los chats, formal en el correo y técnico en editores de código y terminales.
- **Tiene en cuenta lo ya escrito.** Lee el texto que hay antes del cursor para continuar la frase y escribir los nombres igual.
- **Dictados largos.** Con Groq, las grabaciones largas se cortan en las pausas y se transcriben mientras sigues hablando, así que el texto está listo un segundo después de terminar.
- **Idiomas.** Dicta en cualquier idioma que admita el reconocimiento de Apple, alterna entre español e inglés automáticamente y, si quieres, traduce el resultado a otro idioma.
- **Historial y estadísticas.** Busca dictados anteriores, cópialos de nuevo y consulta tus palabras por minuto y el tiempo ahorrado.

## Requisitos

- macOS 27 o posterior en un Mac con chip de Apple.
- Opcional: Apple Intelligence activado, para pulir el texto en el Mac.
- Opcional: una clave gratuita de [console.groq.com](https://console.groq.com/keys), para usar el motor Groq.

## Instalación

1. Descarga el último `.dmg` desde [Releases](https://github.com/kevin9038440334/stepbro-whispr/releases/latest).
2. Ábrelo y arrastra **stepbro whispr** a **Aplicaciones**.
3. Abre la app. La primera vez te guía por los permisos de micrófono y Accesibilidad, la tecla para dictar y el idioma.

La app no está notarizada por Apple, así que macOS la bloquea la primera vez. Ve a **Ajustes del Sistema › Privacidad y seguridad** y pulsa **Abrir igualmente**. Solo hay que hacerlo una vez.

Si usas Fn como tecla, en **Ajustes del Sistema › Teclado** cambia la acción de la tecla del globo a **No hacer nada**, para que el sistema no reaccione al pulsarla.

## Motores de dictado

Se elige uno en **Ajustes › Motor de dictado**.

| | Apple | Groq |
| --- | --- | --- |
| Reconocimiento de voz | `SpeechAnalyzer`, en el Mac | Whisper Large v3 Turbo o v3 |
| Pulido del texto | Apple Intelligence, en el Mac | Qwen 3.8 27B, GPT OSS 20B o 120B |
| Internet | No hace falta | Necesario |
| Coste | Gratis | Tiene plan gratuito |

Con Groq, el reconocimiento de Apple sigue funcionando en paralelo como respaldo: si la red va lenta o Groq falla, el texto llega igualmente. Si el modelo elegido llega a su límite de uso, responde otro.

## Privacidad

- Con el motor de Apple, el audio y el texto no salen de tu Mac.
- Con Groq, el audio grabado y el texto que hay que pulir se envían a Groq. Si **Tener en cuenta lo ya escrito** está activado, también se envía ese fragmento. No se envía nada a ningún otro sitio.
- La clave de Groq se guarda en `~/Library/Application Support/stepbro whispr/` y solo tu usuario puede leerla.
- El historial, el diccionario y los ajustes se quedan en tu Mac.

## Compilar desde el código

Necesitas Xcode 27 (Swift 6.4).

```sh
git clone https://github.com/kevin9038440334/stepbro-whispr.git
cd stepbro-whispr
./scripts/create-certificate.sh   # una vez: certificado local para firmar
make run                          # compila y abre build/stepbro whispr.app
```

| Comando | Qué hace |
| --- | --- |
| `make build` | Compila y firma `build/stepbro whispr.app` |
| `make run` | Compila y abre la app |
| `make install` | Copia la app a `/Applications` |
| `make dmg` | Crea el instalador `build/stepbro-whispr-<versión>.dmg` |
| `make test` | Ejecuta los tests |
| `make clean` | Borra lo compilado |

Con un certificado de firma estable, macOS recuerda los permisos de la app entre compilaciones. `scripts/build.sh` usa, por orden, `SIGN_IDENTITY`, un certificado «Apple Development», el certificado local «Susurro Dev» o una firma ad hoc.

El identificador de la app es `com.susurro.Susurro`, del nombre original del proyecto. Se mantiene a propósito: si cambiara, macOS la trataría como otra app y se perderían los permisos, el historial y los ajustes.

## Estructura

```
Sources/StepbroWhisprCore/   Lógica de texto sin interfaz, con tests
  SmartFormatter.swift         puntuación, listas, comandos dictados, correos
  PolishPrompt.swift           instrucciones para los modelos y redes de seguridad
  GroqClient.swift             API de Groq (Whisper y modelos de texto)
  TranscriptChooser.swift      elige entre la transcripción de Whisper y la de Apple
  Vocabulary.swift             diccionario
  Snippets.swift               atajos de texto
  LongDictation.swift          une las partes de un dictado largo
  PauseDetector.swift          busca pausas para cortar las grabaciones largas
Sources/StepbroWhispr/
  App/     ciclo de vida, coordinación y preferencias
  Audio/   captura del micrófono y reconocimiento de voz
  System/  tecla global, pegado, permisos y texto antes del cursor
  Text/    procesado del texto, Apple Intelligence, Groq e historial
  UI/      ventana principal, bienvenida y barra flotante
Tests/StepbroWhisprCoreTests/
scripts/   compilación, firma, icono e instalador
```

## Licencia

stepbro whispr es de código disponible bajo la [PolyForm Noncommercial License 1.0.0](LICENSE.md).

Puedes usarla, estudiarla, modificarla y compartirla para cualquier fin no comercial: uso personal, estudio, proyectos por hobby y uso en organizaciones sin ánimo de lucro, educativas o públicas. No se permite venderla ni usarla con fines comerciales. Cualquier copia o versión modificada debe conservar la licencia y la línea `Required Notice` con el crédito del autor.

Para un uso comercial, contacta con el autor a través de [GitHub](https://github.com/kevin9038440334).

## Autor

Creada por [kevin9038440334](https://github.com/kevin9038440334).
