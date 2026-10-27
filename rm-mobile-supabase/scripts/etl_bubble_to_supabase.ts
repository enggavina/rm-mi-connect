/** ETL canônico: paginação, referências estritas e checkpoints persistentes. */
import { runEtl } from '../../desktop/src/server/bridge/etl';
runEtl().catch(error => { console.error(error instanceof Error ? error.message : 'Falha no ETL'); process.exitCode = 1; });
