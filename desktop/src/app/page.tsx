import Image from 'next/image';

export default function Home() {
  return <main>
    <header>
      <div className="brand">
        <Image src="/mi-electric-brasil.svg" alt="MI Electric Brasil" width={82} height={81} priority />
        <span className="brand-name">EM<span>MI Electric Brasil</span></span>
      </div>
      <span className="phase"><span aria-hidden="true" />Desktop em preparação</span>
    </header>

    <section className="hero" aria-labelledby="hero-title">
      <div className="hero-copy">
        <p className="eyebrow">A OPERAÇÃO, SEMPRE EM MOVIMENTO</p>
        <h1 id="hero-title">Sua célula.<br />Seu projeto.<br /><em>Tudo conectado.</em></h1>
        <p className="intro">O EM acompanha a rotina da MI Electric Brasil, da escolha da célula aos formulários e às fotos de cada projeto.</p>
        <p className="offline-note"><span aria-hidden="true">↗</span>Registre no aplicativo, mesmo sem conexão. Sincronize quando a rede voltar.</p>
      </div>
      <aside className="journey" aria-label="Jornada no aplicativo EM">
        <p className="journey-label">DO INÍCIO À EVIDÊNCIA</p>
        <ol>
          <li><span className="step-number">01</span><div><h2>Célula</h2><p>O seu ponto de partida.</p></div></li>
          <li><span className="step-number">02</span><div><h2>Projeto</h2><p>O trabalho que você vai executar.</p></div></li>
          <li><span className="step-number">03</span><div><h2>Formulários e galeria</h2><p>Respostas, fotos e histórico reunidos.</p></div></li>
        </ol>
        <span className="journey-signature">EM <span>Operação de campo</span></span>
      </aside>
    </section>

    <section className="cards" aria-label="Uma jornada organizada por projeto">
      <article><span>01 / ACESSO</span><h2>Comece pela célula</h2><p>Encontre as células disponíveis para seu operador e concentre-se na sua etapa de trabalho.</p></article>
      <article><span>02 / CONTEXTO</span><h2>Entre no projeto</h2><p>Acompanhe a execução e encontre as informações do equipamento no contexto certo.</p></article>
      <article><span>03 / REGISTRO</span><h2>Abra formulários ou fotos</h2><p>Preencha os registros e consulte a galeria de evidências do projeto, em uma mesma jornada.</p></article>
    </section>

    <footer><strong>EM · MI Electric Brasil</strong><p>A área desktop está sendo preparada para a próxima fase. A operação de campo começa no aplicativo EM.</p></footer>
  </main>;
}
