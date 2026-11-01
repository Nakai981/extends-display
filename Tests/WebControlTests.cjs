const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const fixture = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

async function main() {
  const requests = [], elements = {};
  for (const id of ['screen', 'status', 'text', 'send', 'enter', 'back']) elements[id] = { value: '', getBoundingClientRect: () => ({ left: 10, top: 20, width: 400, height: 200 }) };
  let replaced = null;
  vm.runInNewContext(fixture.viewer, {
    URLSearchParams, location: {search:'?token=session-secret', pathname:'/'},
    history:{replaceState: (...args) => replaced=args},
    document:{getElementById:id=>elements[id]},
    URL:{createObjectURL:()=> 'blob:frame',revokeObjectURL:()=>{}},
    fetch:async (path, options={}) => { requests.push({path,...options}); return {ok:true,blob:async()=>({})}; },
    setTimeout:()=>{}, console
  });
  await new Promise(setImmediate);
  assert.equal(replaced[2], '/');
  assert.equal(requests[0].headers['X-ExtendDesk-Token'], 'session-secret');
  assert.equal(elements.screen.src, 'blob:frame');
  elements.screen.onclick({clientX:210,clientY:120});
  await new Promise(setImmediate);
  const click = requests.find(r=>r.path==='/input');
  assert.equal(click.method,'POST');
  assert.deepEqual(JSON.parse(click.body), {kind:'click',x:0.5,y:0.5});
  assert.equal(click.headers['X-ExtendDesk-Token'],'session-secret');
  elements.text.value = 'Tiếng Việt "quoted"'; elements.send.onclick();
  await new Promise(setImmediate);
  assert.equal(JSON.parse(requests.at(-1).body).text,'Tiếng Việt "quoted"');
  elements.enter.onclick(); await new Promise(setImmediate);
  assert.equal(JSON.parse(requests.at(-1).body).text,'\n');

  const calls=[];
  const element = {focus:()=>calls.push('focus'),dispatchEvent:e=>calls.push(e),scrollHeight:1000,clientHeight:100,scrollBy:(x,y)=>calls.push([x,y]),parentElement:null};
  const document = {elementFromPoint:(x,y)=>{calls.push({x,y}); return element;},body:{}};
  const window = {innerWidth:800,innerHeight:400,scrollBy:(x,y)=>calls.push(['window',x,y])};
  class MouseEvent {constructor(type,options){this.type=type;Object.assign(this,options);}}
  const context = {document,window,MouseEvent,getComputedStyle:()=>({overflowY:'auto'})};
  const run = (index,args,extra={}) => vm.runInNewContext(`(function(x,y,width,height,secondary,dx,dy,text){${fixture.browser[index]}})`, {...context,...extra})(...args);
  run(0,[100,50,400,200,false]);
  assert.deepEqual({...calls[0]}, {x:200,y:100});
  assert.equal(calls.filter(x=>x.type==='click').length,1);
  calls.length=0;run(1,[100,50,400,200,false,4,25]);
  assert.deepEqual(Array.from(calls.at(-1)),[4,25]);

  class HTMLInputElement {
    constructor(){this._value='ab';this.selectionStart=1;this.selectionEnd=1;this.events=[];this.tagName='INPUT';}
    get value(){return this._value;} set value(v){this._value=v;}
    setSelectionRange(start,end){this.selectionStart=start;this.selectionEnd=end;}
    dispatchEvent(event){this.events.push(event.type);}
  }
  class HTMLTextAreaElement extends HTMLInputElement {}
  class Event {constructor(type){this.type=type;}}
  const input = new HTMLInputElement(); document.activeElement=input;
  const extra={HTMLInputElement,HTMLTextAreaElement,Event};
  run(2,[0,0,1,1,false,0,0,'Việt " $()'],extra);
  assert.equal(input.value,'aViệt " $()b');
  assert.deepEqual(input.events,['input','change']);
  run(2,[0,0,1,1,false,0,0,'\b'],extra);
  assert.equal(input.value,'aViệt " $(b');
  let submitted=false;input.form={requestSubmit:()=>submitted=true};
  run(2,[0,0,1,1,false,0,0,'\n'],extra);assert.equal(submitted,true);
  console.log('PASS: LAN viewer auth headers/control coordinates/Unicode; browser viewport mapping, nested scroll, text editing, deletion and submit.');
}
main().catch(error=>{console.error(error);process.exit(1);});
