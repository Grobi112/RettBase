{{flutter_js}}
{{flutter_build_config}}

// Flutter in festen Container rendern, damit HTML-Loader erhalten bleibt (kein Flackern)
_flutter.loader.load({
  config: {
    hostElement: document.getElementById('flutter_host')
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  }
});
