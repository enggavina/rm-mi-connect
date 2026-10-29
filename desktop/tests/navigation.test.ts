import test from 'node:test';
import assert from 'node:assert/strict';
import { activePortalItem, portalNavigation } from '../src/components/web/navigation';

test('module navigation reuses existing routes and exposes only explicitly permitted entries', () => {
  const groups = portalNavigation(['em.portal.read', 'em.projects.read']);
  assert.deepEqual(groups.map(group => group.label), ['Operação', 'Planejamento']);
  assert.deepEqual(groups.flatMap(group => group.items.map(item => item.href)), ['/painel', '/recebimentos', '/projetos']);
  assert.deepEqual(portalNavigation([]), []);
  assert.equal(portalNavigation(['em.portal.read', 'em.catalogs.read']).flatMap(group => group.items).some(item => item.href.startsWith('/engenharia')), false);
});

test('the most specific matching path owns the active entry without prefix collisions', () => {
  const items = portalNavigation().flatMap(group => group.items);
  assert.equal(activePortalItem('/engenharia/titulos/abc/editar', items)?.href, '/engenharia/titulos');
  assert.equal(activePortalItem('/engenharia/abc', items)?.href, '/engenharia');
  assert.equal(activePortalItem('/projetos/abc', items)?.href, '/projetos');
  assert.equal(activePortalItem('/projetos-outro', items), undefined);
});
