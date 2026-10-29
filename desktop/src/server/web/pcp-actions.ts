'use server';

import { actionUser, mutate } from './mutation';
import { createPcpActions } from './pcp-mutations';

const actions = createPcpActions({ actionUser, mutate });
export async function saveCellQueue(input: unknown) { return actions.saveCellQueue(input); }
