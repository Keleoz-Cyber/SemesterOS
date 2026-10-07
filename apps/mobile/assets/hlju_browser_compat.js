// The portal constructs an utterance while loading its common Vue helpers.
// Android WebView has no speech engine. Keep that optional descriptor usable,
// and report synthesis-unavailable if speech is actually requested.
(() => {
  if (location.origin !== 'http://xsxk.hlju.edu.cn') return;
  if (window === window.top) {
    // The school's viewport locks zoom and clips its first-use guide on a phone.
    // Android's overview mode fits this width; users can then zoom in as needed.
    const observer = new MutationObserver(() => fitViewport());
    function fitViewport() {
      const meta = document.querySelector('meta[name="viewport"]');
      if (!meta) return false;
      meta.content = 'width=1024,user-scalable=yes';
      observer.disconnect();
      return true;
    }
    observer.observe(document, {childList:true,subtree:true});
    document.addEventListener('DOMContentLoaded', () => {
      if (!document.querySelector('meta[name="viewport"]')) {
        const meta = document.createElement('meta');
        meta.name = 'viewport';
        document.head.appendChild(meta);
      }
      fitViewport();
      observer.disconnect();
    }, {once:true});
    fitViewport();
  }
  if (typeof window.SpeechSynthesisUtterance !== 'function') {
    window.SpeechSynthesisUtterance = class extends EventTarget {
      constructor(text = '') {
        super();
        this.text = text;
        this.lang = '';
        this.voice = null;
        this.volume = 1;
        this.rate = 1;
        this.pitch = 1;
        this.onerror = null;
      }
    };
  }
  if (window.speechSynthesis == null) {
    window.speechSynthesis = new class extends EventTarget {
      get speaking() { return false; }
      get pending() { return false; }
      get paused() { return false; }
      getVoices() { return []; }
      cancel() {}
      pause() {}
      resume() {}
      speak(utterance) {
        queueMicrotask(() => {
          const event = new Event('error');
          Object.defineProperty(event, 'error', {value: 'synthesis-unavailable'});
          utterance.dispatchEvent(event);
          if (typeof utterance.onerror === 'function') utterance.onerror(event);
        });
      }
    };
  }
})();
