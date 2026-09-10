const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname, '../SessionModel.js'), 'utf8'), model);
const snapshot = {
  agents: [
    {paneId:'p1', tabId:'t1', workspaceId:'w1', status:'blocked', terminalTitle:'Review build', agent:'codex'},
    {paneId:'p2', tabId:'t1', workspaceId:'w1', status:'done', lastActiveAt:20, lastSeenAt:10},
    {paneId:'p3', tabId:'t2', workspaceId:'w1', status:'working'},
    {paneId:'p4', tabId:'t2', workspaceId:'w1', status:'done', lastActiveAt:10, lastSeenAt:20},
    {paneId:'p5', tabId:'t2', workspaceId:'w1', status:'idle', lastActiveAt:5, lastSeenAt:9},
    {paneId:'p1', tabId:'t1', workspaceId:'w1', status:'idle', host:'remote', focused:true}
  ],
  shellPanes: [{paneId:'p6', tabId:'t1', workspaceId:'w1', kind:'shell', agent:'shell', cwd:'/projects/my-app', terminalTitle:'npm run dev'}],
  workspaces: [{workspaceId:'w1', label:'Local', number:1}, {workspaceId:'w1', label:'Remote', host:'remote'}],
  tabs: [{tabId:'t1', workspaceId:'w1', label:'1'}, {tabId:'t2', workspaceId:'w1', label:'Build'}, {tabId:'t1', workspaceId:'w1', host:'remote'}]
};
const build = (view, query='', scope=null, expanded=true, newest=true) => Array.from(model.build(snapshot,view,query,scope,expanded,newest));
const selectable = rows => rows.filter(r=>r.kind!=='heading');
assert.deepEqual(build('agents').filter(r=>r.kind==='heading').map(r=>r.title), ['Needs you','Ready · unseen','Working','Recent']);
assert.equal(selectable(build('agents')).length, snapshot.agents.length);
assert.equal(selectable(build('shells')).length, snapshot.shellPanes.length);
assert.equal(selectable(build('tabs')).length, snapshot.tabs.length);
assert.equal(selectable(build('spaces')).length, snapshot.workspaces.length);
assert.equal(model.bucket(snapshot.agents[3]), 'recent', 'seen completion must not be ready');
assert.equal(selectable(build('agents','p4',null,false)).length,1,'search reveals collapsed recent matches');
assert.equal(selectable(build('agents','codex Review')).length,1,'search terms match across title and agent');
assert.equal(selectable(build('shells','my-app')).length,1,'shells are searchable by cwd');
assert.equal(selectable(build('agents','zzzz')).length,0);
const local = build('spaces').find(r=>!r.item.host);
const remote = build('spaces').find(r=>r.item.host);
assert.notEqual(local.key,remote.key,'identical IDs on different hosts stay distinct');
assert.equal(remote.score,1,'local blocked agent must not leak urgency into remote workspace');
assert(selectable(build('detail','',local)).every(r=>!r.item.host),'drilldown retains host scope');
assert.equal(model.paneForTab(snapshot,snapshot.tabs[0]).paneId,'p1');
assert.equal(model.paneForTab(snapshot,snapshot.tabs[0]).host,undefined,'focused remote pane must not replace local tab target');
assert.equal(model.paneForTab(snapshot,snapshot.tabs[2]).host,'remote');
assert.equal(model.route('http://localhost:8787/base?x=1&s=old#anchor','/pane/p%3A1','work space',{host:'a&b'}),'http://localhost:8787/base/pane/p%3A1?x=1&s=work%20space&h=a%26b');
assert.equal(model.build({},'agents','',null,true,true).length,0);
assert.equal(model.webUrl(snapshot,'http://localhost:8787','work space',model.row(snapshot,snapshot.tabs[2],'tab')),'http://localhost:8787/pane/p1?s=work%20space&h=remote','copied tab URL targets its scoped pane');
assert.equal(model.webUrl(snapshot,'http://localhost:8787','',local),'http://localhost:8787/space/w1');
assert.equal(model.webUrl(snapshot,'http://localhost:8787','other',null),'http://localhost:8787?s=other');
assert.equal(model.webUrl(snapshot,'http://localhost:8787','',model.row(snapshot,{tabId:'empty',workspaceId:'w1'},'tab')),'http://localhost:8787/space/w1','empty tab link falls back to its own workspace');
console.log('Swarm model checks passed: triage, all actions, filtering, scopes, and routes.');
