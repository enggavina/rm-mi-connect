export async function register(){
  if(process.env.NEXT_RUNTIME==='nodejs'){
    const{startProjectDeleteCleanup}=await import('./server/web/project-delete-cleanup');startProjectDeleteCleanup();
  }
}
