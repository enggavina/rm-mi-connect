'use server';
import {actionUser,mutate} from './mutation';
import {createProjectRouteCellActions} from './project-route-cell-mutations';
const actions=createProjectRouteCellActions({actionUser,mutate});
export async function manageProjectRouteCell(input:unknown){return actions.manageProjectRouteCell(input);}
