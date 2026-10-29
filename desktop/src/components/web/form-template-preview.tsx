'use client';
import { useState } from 'react';
import { templateSections, ordered, type TemplateContent, type TemplateQuestion, type TemplateChoices } from './form-template-model';
import s from './form-template.module.css';

function PreviewQuestion({ question: q, choices }: { question: TemplateQuestion; choices: TemplateChoices }) {
  const items = ordered(q.items), [na, setNa] = useState(false), unit = choices.dimensions.find(item => item.option_key === q.dimensoes)?.bubble_display;
  const label = `Prévia: ${q.enunciado || 'Questão sem enunciado'}`;
  let field;
  switch (q.tipo) {
    case 'texto_curto': case 'numero': field = <input aria-label={label} placeholder={q.tipo === 'numero' ? 'Informe o valor' : 'Resposta curta'} inputMode={q.tipo === 'numero' ? 'decimal' : 'text'} />; break;
    case 'texto_longo': field = <textarea aria-label={label} placeholder="Resposta longa" />; break;
    case 'lista_suspensa': case 'lista_multi_sele__o': field = <select aria-label={label} multiple={q.tipo === 'lista_multi_sele__o'} defaultValue={q.tipo === 'lista_multi_sele__o' ? [] : ''}>{q.tipo === 'lista_suspensa' && <option value="">Selecione</option>}{items.map(item => <option key={item.id} value={item.id}>{item.descricao || 'Opção sem descrição'}</option>)}</select>; break;
    case 'escolha__nica': case 'caixas_de_sele__o': field = <div style={{ display: 'grid', gap: 12 }}>{items.map(item => <label className="check-label" key={item.id}><input type={q.tipo === 'escolha__nica' ? 'radio' : 'checkbox'} name={`preview-${q.id}`} value={item.id} />{item.descricao || 'Opção sem descrição'}</label>)}</div>; break;
    case 'data': case 'hora': { const interval = q.subtipo === 'intervalo_de_datas' || q.subtipo === 'intervalo_de_hor_rios'; field = <div className="form-grid"><div className="field"><label>{interval ? 'Início' : q.tipo === 'data' ? 'Data' : 'Hora'}<input aria-label={`${label}${interval ? ' — início' : ''}`} type={q.tipo === 'data' ? 'date' : 'time'} /></label></div>{interval && <div className="field"><label>Fim<input aria-label={`${label} — fim`} type={q.tipo === 'data' ? 'date' : 'time'} /></label></div>}</div>; break; }
    case 'foto': field = <div className={s.media}>Captura ou seleção de fotos disponível no aplicativo.</div>; break;
    case 'foto_antes_depois': field = <div className="form-grid"><div className={s.media}>Foto antes</div><div className={s.media}>Foto depois</div></div>; break;
    case 'assinatura': field = <div className={s.media}>Área de assinatura disponível no aplicativo.</div>; break;
    case 'colaborador': case 'cliente': field = <><select aria-label={label} defaultValue=""><option value="">{q.tipo === 'cliente' ? 'Selecionar cliente' : 'Selecionar colaborador'}</option></select><span className={s.notes}>{q.tipo === 'cliente' ? 'As opções são os clientes disponíveis no aplicativo.' : `As opções são os colaboradores ativos${q.colaborador_filtro_perfil ? ` do perfil ${choices.profiles.find(profile => profile.option_key === q.colaborador_filtro_perfil)?.bubble_display || q.colaborador_filtro_perfil}` : ''}.`}</span></>; break;
    default: field = <p className={s.notes}>Tipo de questão indisponível nesta prévia.</p>;
  }
  return <div className={s.previewQuestion}><h3>{q.indice}. {q.enunciado || 'Questão sem enunciado'}{q.obrigatorio && ' *'}</h3>{q.subtitulo && <p className={s.subtitle}>{q.subtitulo}</p>}{q.tag && <p className={s.notes}>{q.tag}</p>}
    <div className="field">{unit && <span>Unidade: {unit}</span>}{na ? <div className="notice">Não se aplica (N/A)</div> : field}</div><button type="button" className="button small secondary" style={{ marginTop: 16 }} onClick={() => setNa(value => !value)}>{na ? 'Preencher questão' : 'Marcar N/A na prévia'}</button>
  </div>;
}
function PreviewSection({ section, choices }: { section: ReturnType<typeof templateSections>[number]; choices: TemplateChoices }) {
  const [open, setOpen] = useState(false);
  return <details onToggle={event => setOpen(event.currentTarget.open)}><summary>{section.title} <span className={s.notes}>· {section.questions.length} questões</span></summary>{open && <>{section.description && <p className={s.subtitle} style={{ padding: '16px 18px 0' }}>{section.description}</p>}{section.questions.map(question => <PreviewQuestion key={question.id} question={question} choices={choices} />)}{!section.questions.length && <p className={s.notes} style={{ padding: 18 }}>Nenhuma questão neste subtítulo.</p>}</>}</details>;
}
export function FormTemplatePreview({ content, choices }: { content: TemplateContent; choices: TemplateChoices }) {
  return <div className={s.preview}><h2 style={{ fontSize: 20 }}>{content.titulo || 'Modelo sem título'}</h2>{content.descricao && <p className={s.subtitle}>{content.descricao}</p>}<p className={s.notes}>Prévia de preenchimento. As respostas desta tela não são salvas. Fotos e assinaturas são capturadas no aplicativo.</p>{templateSections(content.questions).map(section => <PreviewSection section={section} key={section.id} choices={choices} />)}{!content.questions.length && <p className={s.notes}>Adicione questões para visualizar o modelo.</p>}</div>;
}
