import { MiLoader } from './mi-loader';
import styles from './login-progress.module.css';

export function LoginProgress({ label = 'Entrando no EM…', onCancel }: { label?: string; onCancel?: () => void }) {
  return <div className={styles.backdrop} data-login-progress>
    <div className={styles.content}>
      <MiLoader label={label} />
      <p className={styles.brand}>MI Electric Brasil</p>
      {onCancel && <div className={styles.actions}><button className="button secondary" type="button" onClick={onCancel}>Cancelar entrada</button></div>}
    </div>
  </div>;
}
