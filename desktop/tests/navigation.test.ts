import test from 'node:test';
import assert from 'node:assert/strict';
import { activePortalItem, portalHomeModules, portalNavigation, portalShortcuts } from '../src/components/web/navigation';

test('module navigation reuses existing routes and exposes only explicitly permitted entries', () => {
  const groups = portalNavigation(['em.portal.read', 'em.projects.read']);
  assert.deepEqual(groups.map(group => group.label), ['Operação']);
  assert.deepEqual(groups.flatMap(group => group.items.map(item => item.href)), ['/painel', '/projetos', '/recebimentos']);
  assert.deepEqual(portalNavigation([]), []);
  assert.equal(portalNavigation(['em.portal.read', 'em.catalogs.read']).flatMap(group => group.items).some(item => item.href.startsWith('/engenharia')), false);
});

test('the most specific matching path owns the active entry without prefix collisions', () => {
  const items = portalNavigation().flatMap(group => group.items);
  assert.equal(activePortalItem('/engenharia/titulos/abc/editar', items)?.href, '/engenharia/titulos');
  assert.equal(activePortalItem('/engenharia/abc', items)?.href, '/engenharia');
  assert.equal(activePortalItem('/projetos/abc', items)?.href, '/projetos');
  assert.equal(activePortalItem('/projetos-outro', items), undefined);
  assert.equal(activePortalItem('/planejamento/fila', items)?.href, '/planejamento/fila');
  assert.equal(activePortalItem('/planejamento/carga', items)?.href, '/planejamento/carga');
});

test('home cards retain every existing functional route while the sidebar has only five shortcuts', () => {
  const modules = portalHomeModules(), cards = modules.flatMap(group => group.items), shortcuts = portalShortcuts();
  assert.deepEqual(modules.map(group => group.label), ['Operação', 'Planejamento', 'Cadastros']);
  assert.equal(cards.length, 12); assert.equal(new Set(cards.map(item => item.href)).size, cards.length);
  assert.deepEqual(cards.map(item => item.href).sort(), ['/projetos', '/recebimentos', '/formularios', '/aprovacoes', '/cronograma', '/planejamento', '/planejamento/fila', '/planejamento/carga', '/cadastros', '/engenharia', '/engenharia/titulos', '/modelos-formularios'].sort());
  assert.deepEqual(shortcuts.map(item => item.href), ['/painel', '/projetos', '/cronograma', '/formularios', '/aprovacoes']);
  for (const card of cards) { assert.ok(card.description.trim()); assert.ok(card.label.trim()); assert.ok(card.href.startsWith('/')); }
});

test('cards and shortcuts independently honor the exact capability for each entry', () => {
  assert.deepEqual(portalHomeModules(['em.portal.read']), []);
  assert.deepEqual(portalShortcuts(['em.portal.read']).map(item => item.href), ['/painel']);
  const every = portalNavigation().flatMap(group => group.items);
  for (const item of every) {
    const cards = portalHomeModules([item.capability]).flatMap(group => group.items);
    const shortcuts = portalShortcuts([item.capability]);
    assert.ok(cards.every(card => card.capability === item.capability));
    assert.ok(shortcuts.every(shortcut => shortcut.capability === item.capability));
    if (item.href !== '/painel') assert.ok(cards.some(card => card.href === item.href));
    if (item.shortcutOrder !== undefined) assert.ok(shortcuts.some(shortcut => shortcut.href === item.href));
    assert.ok(portalShortcuts(every.filter(candidate => candidate.capability !== item.capability).map(candidate => candidate.capability)).length <= 5);
  }
  assert.deepEqual(portalHomeModules([]), []); assert.deepEqual(portalShortcuts([]), []);
});
