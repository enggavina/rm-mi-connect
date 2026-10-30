import test from 'node:test';
import assert from 'node:assert/strict';
import { handleEngineeringReload, navigateAfterEngineeringSave } from '../src/components/web/engineering-save-navigation';

function browser(href: string) {
  const events: unknown[] = [], state = { preserved: { tree: ['native-navigation'] } };
  return { events, state, surface: { location: { href, assign: (target: string) => { events.push(['assign', target]); }, reload: () => { events.push(['reload']); } },
    history: { state, replaceState: (data: unknown, title: string, target?: string | URL | null) => { events.push(['replaceState', data, title, target]); } } } };
}

test('saving to the current anchored allocation reloads the server snapshot and preserves history state', () => {
  const href = 'https://em.example.invalid/projetos/p?tab=planejamento&allocation=a#celula-a', mock = browser(href);
  navigateAfterEngineeringSave('/projetos/p?tab=planejamento&allocation=a#celula-a', mock.surface);
  assert.deepEqual(mock.events, [['replaceState', mock.state, '', href], ['reload']]);
  assert.equal((mock.events[0] as unknown[])[1], mock.state);
});

test('changing or clearing a hash on the same project context also forces a server refresh', () => {
  for (const [current, target] of [
    ['https://em.example.invalid/projetos/p?tab=planejamento', '#celula-a'],
    ['https://em.example.invalid/projetos/p?tab=planejamento#celula-a', '#celula-b'],
    ['https://em.example.invalid/projetos/p?tab=planejamento#celula-a', '/projetos/p?tab=planejamento'],
  ]) {
    const mock = browser(current); navigateAfterEngineeringSave(target, mock.surface);
    assert.deepEqual(mock.events, [['replaceState', mock.state, '', new URL(target, current).href], ['reload']]);
  }
});

test('different native contexts and destinations without a hash keep the existing navigation', () => {
  const href = 'https://em.example.invalid/cronograma?project=p&allocation=a';
  for (const target of ['/cronograma?project=p&allocation=a', '/cronograma?project=p&allocation=b#celula-b', '/projetos/p#celula-a', 'https://other.example.invalid/cronograma?project=p&allocation=a#cell']) {
    const mock = browser(href); navigateAfterEngineeringSave(target, mock.surface);
    assert.deepEqual(mock.events, [['assign', target]]);
  }
});

test('explicit anchored reload links refresh the snapshot on an ordinary primary click', () => {
  const href = 'https://em.example.invalid/projetos/p?tab=planejamento&allocation=a#celula-a', mock = browser(href);
  let prevented = false;
  handleEngineeringReload({ defaultPrevented: false, button: 0, ctrlKey: false, metaKey: false, shiftKey: false, altKey: false,
    preventDefault: () => { prevented = true; } }, href, mock.surface);
  assert.equal(prevented, true);
  assert.deepEqual(mock.events, [['replaceState', mock.state, '', href], ['reload']]);
});

test('reload links leave prevented, modified and non-primary clicks to native browser behavior', () => {
  for (const change of [{ defaultPrevented: true }, { button: 1 }, { button: 2 }, { ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { altKey: true }]) {
    const mock = browser('https://em.example.invalid/projetos/p#cell');
    handleEngineeringReload({ defaultPrevented: false, button: 0, ctrlKey: false, metaKey: false, shiftKey: false, altKey: false,
      preventDefault: () => assert.fail('A modified/prevented click must retain its default behavior.'), ...change }, '/projetos/p#cell', mock.surface);
    assert.deepEqual(mock.events, []);
  }
});
