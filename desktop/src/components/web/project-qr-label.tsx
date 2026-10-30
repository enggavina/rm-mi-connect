'use client';

import { useEffect, useRef, useState } from 'react';
import type { ProjectQrProject } from '@/server/web/project-qr-policy';
import { projectQrImageHref, projectQrLabel, projectQrSummary } from './project-qr-model';
import { Icon } from './icons';
import s from './project-qr.module.css';

export function ProjectQrLabel({ project }: { project: ProjectQrProject }) {
  const [image, setImage] = useState<'loading' | 'ready' | 'failed'>('loading'), [attempt, setAttempt] = useState(0);
  const [copyMessage, setCopyMessage] = useState(''), [printMessage, setPrintMessage] = useState('');
  const identifier = useRef<HTMLInputElement>(null), qrImage = useRef<HTMLImageElement>(null);
  const label = projectQrLabel(project), summary = projectQrSummary(project);
  useEffect(() => {
    // A fast SSR image can finish before React attaches the load/error handlers.
    const element = qrImage.current;
    if (element?.complete) setImage(element.naturalWidth > 0 ? 'ready' : 'failed');
  }, [attempt, project.id]);
  async function copy() {
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(project.id);
      setCopyMessage('Identificador copiado.');
    } catch {
      identifier.current?.focus(); identifier.current?.select();
      setCopyMessage('Não foi possível copiar automaticamente. O identificador foi selecionado para você copiar.');
    }
  }
  function print() {
    setPrintMessage('');
    try { if (typeof window.print !== 'function') throw new Error('Printing unavailable'); window.print(); }
    catch { setPrintMessage('Não foi possível abrir a impressão. Você pode baixar o SVG para imprimir.'); }
  }
  return <div className={s.layout} data-project-qr={project.id}>
    <section className={s.label} aria-label={`Etiqueta de identificação de ${label}`} data-project-qr-label>
      <div className={s.brand}><img src="/mi-electric-brasil.svg" width="44" height="44" alt="" /><div><strong>EM</strong><span>MI Electric Brasil</span></div></div>
      <p className={s.kicker}>IDENTIFICAÇÃO DO PROJETO</p>
      <h2>{label}</h2>{summary && <p className={s.summary}>{summary}</p>}
      <div className={s.qr} aria-busy={image === 'loading'}>
        {image !== 'failed' && <img ref={qrImage} key={attempt} src={projectQrImageHref(project.id)} width="320" height="320" alt={`QR de identificação de ${label}`} referrerPolicy="no-referrer" decoding="sync" onLoad={() => setImage('ready')} onError={() => setImage('failed')} />}
        {image === 'loading' && <p className={s.loading} role="status">Carregando QR…</p>}
        {image === 'failed' && <div className={s.imageFailure} role="status"><Icon name="image" size={30} /><p>Não foi possível carregar o QR agora.</p><button className="button small secondary" type="button" onClick={() => { setImage('loading'); setAttempt(value => value + 1); }}>Tentar carregar QR</button></div>}
      </div>
      <p className={s.identifier} data-project-qr-identifier>{project.id}</p>
      <p className={s.labelInstruction}>No aplicativo EM, selecione a célula e use <strong>Ler QR Code</strong>.</p>
      <p className={s.internal}>Identificação interna · acesso conforme suas permissões</p>
    </section>
    <section className={s.screen} aria-label="Usar a identificação por QR">
      <div className={s.controls}><button type="button" className="button" disabled={image !== 'ready'} onClick={print}><Icon name="file" size={15} />Imprimir etiqueta</button><a className="button secondary" href={projectQrImageHref(project.id, true)} download><Icon name="download" size={15} />Baixar SVG</a></div>{printMessage && <p className={s.note} role="status">{printMessage}</p>}
      <div className={s.help}><h2>Como usar no aplicativo</h2><ol><li>Abra o aplicativo EM atualizado e selecione uma célula permitida.</li><li>Na lista de projetos, toque em <strong>Ler QR Code</strong> e aponte a câmera para a etiqueta.</li><li>O projeto será aberto quando estiver disponível para você nessa célula.</li></ol><p>Sem conexão, o projeto precisa estar sincronizado no dispositivo. O QR identifica o projeto e mantém as permissões de acesso existentes.</p></div>
      <div className={s.manual}><label htmlFor="project-qr-identifier">Identificador do projeto</label><input ref={identifier} id="project-qr-identifier" value={project.id} readOnly onFocus={event => event.currentTarget.select()} /><button type="button" className="button small secondary" onClick={() => { void copy(); }}>Copiar identificador</button>{copyMessage && <p role="status">{copyMessage}</p>}</div>
      <p className={s.note}>A etiqueta impressa contém apenas a identificação exibida ao lado. Imprima depois de conferir se o QR foi carregado corretamente.</p>
    </section>
  </div>;
}
