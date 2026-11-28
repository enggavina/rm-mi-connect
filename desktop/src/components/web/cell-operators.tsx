'use client';

import { useActionState } from 'react';
import { changeCellOperator } from '@/server/web/cell-operator-actions';
import type { CellOperator } from '@/server/web/cell-operator-access';

export function CellOperators({ cell, operators }: { cell: string; operators: CellOperator[] }) {
  const [feedback, submit, pending] = useActionState(changeCellOperator, { message: '', error: false });
  return <section className="panel">
    <div className="panel-header"><h2>Operadores da célula</h2></div>
    <div className="panel-content">
      <p className="table-subtitle">Selecione operadores vinculados à oficina na Central de Acessos. A lista de células é atualizada no aplicativo quando ele se conecta.</p>
      {feedback.message && <p role={feedback.error ? 'alert' : 'status'}>{feedback.message}</p>}
      {operators.length === 0 ? <p>Nenhum operador disponível. Confira os vínculos da oficina em Acessos.</p> :
        <div className="table-scroll"><table className="data-table">
          <thead><tr><th>Operador</th><th>Acesso à célula</th><th>Ação</th></tr></thead>
          <tbody>{operators.map(operator => <tr key={operator.id}>
            <td>{operator.nome ?? `Operador fora da equipe · ${operator.id.slice(-8)}`}{operator.matricula && <span className="table-subtitle">{operator.matricula}</span>}</td>
            <td>{operator.automatic ? 'Pelo perfil administrativo' : operator.legacy ? 'Vínculo legado' : operator.managed ? (operator.eligible ? 'Vinculado' : 'Fora da equipe atual') : 'Sem vínculo'}</td>
            <td>{(operator.managed || operator.eligible && !operator.automatic && !operator.legacy) && <form action={submit}>
              <input type="hidden" name="cell" value={cell} />
              <input type="hidden" name="operator" value={operator.id} />
              <input type="hidden" name="revision" value={operator.revision} />
              <input type="hidden" name="enabled" value={operator.managed ? 'revoke' : 'grant'} />
              <button className="button small" type="submit" disabled={pending} aria-label={`${operator.managed ? 'Remover vínculo de' : 'Vincular'} ${operator.nome ?? operator.id.slice(-8)}`}>
                {operator.managed ? 'Remover vínculo' : 'Vincular'}
              </button>
            </form>}</td>
          </tr>)}</tbody>
        </table></div>}
    </div>
  </section>;
}
