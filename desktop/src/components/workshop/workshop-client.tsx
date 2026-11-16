'use client';
import dynamic from 'next/dynamic';
import { MiLoader } from '@/components/web/mi-loader';
const WorkshopApp = dynamic(() => import('./WorkshopApp'), { ssr: false, loading: () => <div className="loading-view"><MiLoader label="Preparando o gêmeo digital…" /></div> });
export function WorkshopClient() { return <WorkshopApp />; }
