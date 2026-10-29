'use server';
import { actionUser, mutate } from './mutation';
import { createFormTemplateActions } from './form-template-mutations';
const actions = createFormTemplateActions({ actionUser, mutate });
export async function createFormTemplate(input: unknown) { return actions.createFormTemplate(input); }
export async function saveFormTemplate(input: unknown) { return actions.saveFormTemplate(input); }
export async function publishFormTemplate(input: unknown) { return actions.publishFormTemplate(input); }
