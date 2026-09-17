# Cartella branding per-cliente

Questa cartella contiene le immagini specifiche del cliente per cui si sta
compilando l'app. Per una nuova build cliente, sostituire:

- `icon.png` — immagine sorgente 1024x1024 px, senza angoli arrotondati né
  trasparenza, usata da flutter_launcher_icons per generare tutte le icone
  native Android/iOS (comando: `flutter pub run flutter_launcher_icons`).
- `logo.png` — logo mostrato nella schermata di login (consigliato: sfondo
  trasparente, proporzioni quadrate o quasi).

Nessuna di queste immagini è presente in questo pacchetto iniziale: vanno
fornite dal cliente (o dal reparto marketing) prima della prima build
white-label. Finché non sono presenti, l'app usa l'icona/il segnaposto
grafico di default di Flutter.
