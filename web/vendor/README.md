Vendored third-party assets

pdf.min.mjs and pdf.worker.min.mjs are Mozilla's PDF.js build (version
4.9.155), copied here verbatim from cdnjs.

  Project: https://mozilla.github.io/pdf.js/
  License: Apache License 2.0
  Files:  https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.9.155/

They are bundled locally rather than loaded from the CDN because ClassCast
is an offline classroom tool: a browser with no internet must still be able
to render a shared PDF.

Syncfusion's Flutter PDF viewer requires the `pdfjsLib` global to exist on
the web platform; web/index.html imports these files to provide it.