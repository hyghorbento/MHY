import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Exercita o código real do HTML com o comportamento de reutilização do SDK.
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const source = html.slice(
  html.indexOf('let sessionRevision = 0;'),
  html.indexOf("\ndocument.addEventListener('visibilitychange'")
);
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}
function harness() {
  const elements = new Map();
  const channels = new Map();
  const active = new Set();
  const messages = [];
  let loads = 0;
  const context = {
    user: null, channel: null, configured: true,
    cart: new Map(), products: [], sales: [], movements: [],
    $: id => {
      if (!elements.has(id)) elements.set(id, {
        textContent: '', classList: { toggle() {} }
      });
      return elements.get(id);
    },
    resetCheckoutKey() {}, render() {}, setDemo() {},
    notify: message => messages.push(message),
    load: async () => { loads++; },
    db: {
      channel(name) {
        if (channels.has(name)) return channels.get(name);
        const instance = {
          state: 'closed',
          on(_event, _filter, callback) {
            if (this.state === 'joined') throw Error('cannot add callbacks after subscribe');
            this.change = callback;
            return this;
          },
          subscribe(callback) {
            this.status = callback;
            this.state = 'joined';
            active.add(this);
            callback('SUBSCRIBED');
            return this;
          }
        };
        channels.set(name, instance);
        return instance;
      },
      async removeChannel(instance) {
        instance.state = 'closed';
        active.delete(instance);
        instance.status?.('CLOSED');
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return { context, channels, active, messages, elements, get loads() { return loads; } };
}
const session = id => ({ user: { id } });

test('eventos repetidos do mesmo usuário mantêm um canal e o carrinho', async () => {
  const h = harness();
  await h.context.applySession(session('owner'));
  h.context.cart.set('produto', 2);
  await Promise.all(Array.from({ length: 5 }, () => h.context.applySession(session('owner'))));
  assert.equal(h.channels.size, 1);
  assert.equal(h.active.size, 1);
  assert.equal(h.loads, 1);
  assert.equal(h.context.cart.get('produto'), 2);
  assert.deepEqual(h.messages, []);
});

test('evento durante carregamento inicial não configura um canal já inscrito', async () => {
  const h = harness(), started = deferred(), release = deferred();
  let count = 0;
  h.context.load = async () => { if (++count === 1) { started.resolve(); await release.promise; } };
  const first = h.context.applySession(session('owner'));
  await started.promise;
  const second = h.context.applySession(session('owner'));
  release.resolve();
  await Promise.all([first, second]);
  assert.equal(h.active.size, 1);
  assert.equal(h.channels.size, 1);
  assert.deepEqual(h.messages, []);
});

test('sair durante o carregamento impede inscrição tardia', async () => {
  const h = harness(), started = deferred(), release = deferred();
  h.context.load = async () => { started.resolve(); await release.promise; };
  const login = h.context.applySession(session('owner'));
  await started.promise;
  const logout = h.context.applySession(null);
  release.resolve();
  await Promise.all([login, logout]);
  assert.equal(h.context.user, null);
  assert.equal(h.context.channel, null);
  assert.equal(h.active.size, 0);
});

test('troca de conta remove canal antigo e ignora suas notificações tardias', async () => {
  const h = harness();
  await h.context.applySession(session('first'));
  const previous = h.context.channel;
  h.context.cart.set('produto', 1);
  await h.context.applySession(session('second'));
  assert.equal(h.context.user.id, 'second');
  assert.equal(h.context.cart.size, 0);
  assert.equal(h.active.size, 1);
  previous.status('CLOSED');
  assert.equal(h.elements.get('connection').textContent, 'Supabase • tempo real');
});

test('canal com erro pode ser reconstruído sem reutilizar instância inscrita', async () => {
  const h = harness();
  await h.context.applySession(session('owner'));
  const previous = h.context.channel;
  previous.state = 'errored';
  await h.context.applySession(session('owner'));
  assert.notEqual(h.context.channel, previous);
  assert.equal(h.channels.size, 2);
  assert.equal(h.active.size, 1);
  assert.deepEqual(h.messages, []);
});

test('falha de carregamento permite nova tentativa e informa erro', async () => {
  const h = harness();
  h.context.load = async () => { throw Error('Falha de rede'); };
  await h.context.applySession(session('owner'));
  assert.deepEqual(h.messages, ['Falha de rede']);
  assert.equal(h.active.size, 0);
  h.context.load = async () => {};
  await h.context.applySession(session('owner'));
  assert.equal(h.active.size, 1);
});
