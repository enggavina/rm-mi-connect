import Image from 'next/image';
import { notFound, redirect } from 'next/navigation';
import { Icon } from '@/components/web/icons';
import { Empty, PageHeading } from '@/components/web/ui';
import { OperationHistory } from './operation-history';
import styles from './operation.module.css';

export function OperationScreen({ workshop, operatorName, children }: {
  workshop?: { name: string; code: string };
  operatorName?: string;
  children: React.ReactNode;
}) {
  return <div className={styles.shell}>
    <OperationHistory />
    <a className="skip-link" href="#operacao-conteudo">Ir para o conteúdo</a>
    <header className={styles.header}>
      <div className={styles.headerInner}>
        <a href="/operacao" className={styles.brand}>
          <Image src="/mi-electric-brasil.svg" alt="" width={40} height={40} />
          <span>EM Operacional</span>
        </a>
        <div className={styles.context}>
          {workshop && <span className={styles.contextText}><strong>{workshop.name}</strong>{operatorName}</span>}
          <form action="/operacao/sair" method="post"><button className="button secondary" type="submit">Sair</button></form>
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

export function operationIssue(status: 'session' | 'forbidden' | 'unavailable' | 'missing') {
  if (status === 'session') redirect('/operacao/login');
  if (status === 'missing') notFound();
  const forbidden = status === 'forbidden';
  return <OperationScreen>
    <PageHeading title={forbidden ? 'Acesso à oficina indisponível' : 'Consulta indisponível'} />
    <section className="panel">
      <Empty icon={forbidden ? 'alert' : 'refresh'} title={forbidden ? 'Confira seus vínculos' : 'Tente novamente'}
        detail={forbidden ? 'Consulte o responsável pelos acessos para verificar o vínculo do dispositivo e do operador.' : 'A operação está temporariamente indisponível.'}>
        <a href={forbidden ? '/operacao/login' : '/operacao'} className="button secondary">{forbidden ? 'Voltar ao acesso' : 'Consultar células'}</a>
      </Empty>
    </section>
  </OperationScreen>;
}
