import test from 'node:test';
import assert from 'node:assert/strict';
import { activePortalItem, portalHomeModules, portalNavigation, portalShortcuts, WORKSHOP_3D_PATH } from '../src/components/web/navigation';

test('module navigation reuses existing routes and exposes only explicitly permitted entries', () => {
  const groups = portalNavigation(['em.portal.read', 'em.projects.read']);
  assert.deepEqual(groups.map(group => group.label), ['Operação']);
  assert.deepEqual(groups.flatMap(group => group.items.map(item => item.href)), ['/painel', '/acompanhamento', '/projetos', '/recebimentos']);
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
  assert.equal(activePortalItem('/painel', items)?.href, '/painel');
  assert.equal(activePortalItem('/acompanhamento', items)?.href, '/acompanhamento');
  assert.equal(activePortalItem('/acompanhamento-outro', items), undefined);
  assert.equal(activePortalItem(WORKSHOP_3D_PATH, items)?.href, WORKSHOP_3D_PATH);
  assert.equal(activePortalItem(`${WORKSHOP_3D_PATH}/oficina`, items)?.href, WORKSHOP_3D_PATH);
});

test('home cards include resource capacity while the sidebar stays compact', () => {
  const modules = portalHomeModules(), cards = modules.flatMap(group => group.items), shortcuts = portalShortcuts();
  assert.deepEqual(modules.map(group => group.label), ['Operação', 'Planejamento', 'Cadastros']);
  assert.equal(cards.length, 13); assert.equal(new Set(cards.map(item => item.href)).size, cards.length);
  assert.deepEqual(cards.map(item => item.href).sort(), ['/projetos', '/recebimentos', '/formularios', '/aprovacoes', '/cronograma', '/planejamento', '/planejamento/fila', '/planejamento/carga', '/planejamento/capacidade', '/cadastros', '/engenharia', '/engenharia/titulos', '/modelos-formularios'].sort());
  assert.deepEqual(shortcuts.map(item => item.href), ['/painel', '/acompanhamento', WORKSHOP_3D_PATH, '/projetos', '/cronograma', '/formularios', '/aprovacoes']);
  assert.equal(new Set(shortcuts.map(item => item.href)).size, shortcuts.length);
  for (const card of cards) { assert.ok(card.description.trim()); assert.ok(card.label.trim()); assert.ok(card.href.startsWith('/')); }
});

test('monitoring remains separate from work cards and reuses portal access without granting another application', () => {
  const shortcuts = portalShortcuts(['em.portal.read']);
  assert.deepEqual(shortcuts.map(item => item.href), ['/painel', '/acompanhamento']);
  assert.ok(shortcuts.every(item => item.home === false && item.capability === 'em.portal.read'));
  const workshop = portalShortcuts(['em.portal.read', 'em.projects.read', 'em.planning.read']).find(item => item.href === WORKSHOP_3D_PATH)!;
  assert.equal(workshop.external, undefined);
  assert.equal(workshop.href, '/gemeo-digital');
  for (const missing of ['em.portal.read', 'em.projects.read', 'em.planning.read'] as const) {
    assert.equal(portalShortcuts((['em.portal.read', 'em.projects.read', 'em.planning.read'] as const).filter(cap => cap !== missing)).some(item => item.href === WORKSHOP_3D_PATH), false);
  }
  assert.ok(shortcuts.filter(item => item.href !== WORKSHOP_3D_PATH).every(item => item.external !== true));
  assert.ok(portalHomeModules().flatMap(group => group.items).every(item => !item.external && item.href !== '/acompanhamento'));
  assert.deepEqual(portalShortcuts(['em.documents.read']), []);
});

test('cards and shortcuts independently honor the exact capability for each entry', () => {
  assert.deepEqual(portalHomeModules(['em.portal.read']), []);
  assert.deepEqual(portalShortcuts(['em.portal.read']).map(item => item.href), ['/painel', '/acompanhamento']);
  const every = portalNavigation().flatMap(group => group.items);
  for (const item of every) {
    const granted = [item.capability, ...(item.requires ?? [])];
    const cards = portalHomeModules(granted).flatMap(group => group.items);
    const shortcuts = portalShortcuts(granted);
    assert.ok(cards.every(card => granted.includes(card.capability)));
    assert.ok(shortcuts.every(shortcut => granted.includes(shortcut.capability)));
    if (item.home !== false) assert.ok(cards.some(card => card.href === item.href));
    else assert.ok(!cards.some(card => card.href === item.href));
    if (item.shortcutOrder !== undefined) assert.ok(shortcuts.some(shortcut => shortcut.href === item.href));
    const withoutCapability = every.filter(candidate => candidate.capability !== item.capability).map(candidate => candidate.capability);
    assert.ok(!portalHomeModules(withoutCapability).flatMap(group => group.items).some(card => card.href === item.href));
    assert.ok(!portalShortcuts(withoutCapability).some(shortcut => shortcut.href === item.href));
  }
  assert.deepEqual(portalHomeModules([]), []); assert.deepEqual(portalShortcuts([]), []);
});
