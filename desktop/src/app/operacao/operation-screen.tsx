import Image from 'next/image';
import { notFound, redirect } from 'next/navigation';
import { AccessLayout } from '@/components/web/access';
import { Icon } from '@/components/web/icons';
import { Empty, PageHeading } from '@/components/web/ui';
import { OperationHistory } from './operation-history';
import styles from './operation.module.css';

export type OperationRoute = '/operacao' | '/operacao/validacao';

export function OperationScreen({ workshop, operatorName, base = '/operacao', children }: {
  workshop?: { name: string; code: string };
  operatorName?: string;
  base?: OperationRoute;
  children: React.ReactNode;
}) {
  const validation = base === '/operacao/validacao';
  return <div className={styles.shell}>
    <OperationHistory />
    <a className="skip-link" href="#operacao-conteudo">Ir para o conteúdo</a>
    <header className={styles.header}>
      <div className={styles.headerInner}>
        <a href={base} className={styles.brand}>
          <Image src="/mi-electric-brasil.svg" alt="" width={40} height={40} />
          <span>EM Operacional</span>
        </a>
        <div className={styles.context}>
          {workshop && <span className={styles.contextText}><strong>{workshop.name}</strong>{operatorName}</span>}
          {validation
            ? <a className="button secondary" href="/painel">Voltar ao portal</a>
            : <form action="/operacao/sair" method="post"><button className="button secondary" type="submit">Sair</button></form>}
        </div>
      </div>
    </header>
    <main id="operacao-conteudo" className={styles.content}>{children}</main>
  </div>;
}

export function OperationBack({ href, children }: { href: string; children: React.ReactNode }) {
  return <a href={href} className={styles.back}><Icon name="back" size={16} />{children}</a>;
}

export function projectTitle(project: { numero: string | null; nome: string | null }) {
  return project.numero ? `OS ${project.numero}` : project.nome || 'Projeto em recebimento';
}

export function operationIssue(status: 'session' | 'forbidden' | 'unavailable' | 'missing', base: OperationRoute = '/operacao') {
  const validation = base === '/operacao/validacao';
  if (status === 'session') {
    if (!validation) redirect('/operacao/login');
    return <AccessLayout title="Validação do EM Operacional" description="Entre no portal com a sua conta Microsoft corporativa. No painel, abra Validar EM Operacional.">
      <a href="/login" className="button">Acessar o portal</a>
    </AccessLayout>;
  }
  if (status === 'missing') notFound();
  const forbidden = status === 'forbidden';
  const detail = validation ? 'Consulte o responsável pelos acessos para verificar sua autorização de validação.'
    : 'Consulte o responsável pelos acessos para verificar o vínculo do dispositivo e do operador.';
  return <OperationScreen base={base}>
    <PageHeading title={forbidden ? 'Acesso à oficina indisponível' : 'Consulta indisponível'} />
    <section className="panel">
      <Empty icon={forbidden ? 'alert' : 'refresh'} title={forbidden ? 'Confira seus vínculos' : 'Tente novamente'}
        detail={forbidden ? detail : 'A operação está temporariamente indisponível.'}>
        <a href={forbidden ? validation ? '/painel' : '/operacao/login' : base} className="button secondary">
          {forbidden ? validation ? 'Voltar ao portal' : 'Voltar ao acesso' : 'Consultar células'}
        </a>
      </Empty>
    </section>
  </OperationScreen>;
}

export function OperationNotFoundScreen({ base = '/operacao' }: { base?: OperationRoute }) {
  return <OperationScreen base={base}>
    <PageHeading title="Consulta indisponível" />
    <section className="panel">
      <Empty title="Seleção indisponível" detail="Volte às células para consultar os projetos permitidos.">
        <a href={base} className="button secondary">Voltar às células</a>
      </Empty>
    </section>
  </OperationScreen>;
}
