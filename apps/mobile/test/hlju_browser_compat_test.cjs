const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require('node:path').join(__dirname,'../assets/hlju_browser_compat.js'),'utf8');
function page(origin, original={}) {
  const window = {...original};
  vm.runInNewContext(source,{window,location:{origin},EventTarget,Event,queueMicrotask});
  return window;
}
test('portal initializes its optional utterance, but speech reports unavailable',async()=>{
  const window = page('http://xsxk.hlju.edu.cn');
  const utterance = new window.SpeechSynthesisUtterance('test');
  utterance.lang = 'zh-CN';
  const error = new Promise(resolve=>utterance.addEventListener('error',resolve));
  window.speechSynthesis.speak(utterance);
  assert.equal((await error).error,'synthesis-unavailable');
  assert.equal(window.speechSynthesis.speaking,false);
  assert.equal(window.speechSynthesis.getVoices().length,0);
});
test('real speech APIs and other origins remain unchanged',()=>{
  const constructor = function() {};
  const engine = {};
  const window = page('http://xsxk.hlju.edu.cn',{SpeechSynthesisUtterance:constructor,speechSynthesis:engine});
  assert.equal(window.SpeechSynthesisUtterance,constructor);
  assert.equal(window.speechSynthesis,engine);
  assert.equal(page('https://sso.hlju.edu.cn').SpeechSynthesisUtterance,undefined);
});
