interface SaveNavigationBrowser {
  location: { href: string; assign: (url: string) => void; reload: () => void };
  history: { state: unknown; replaceState: (data: unknown, unused: string, url?: string | URL | null) => void };
}

/** A hash-only navigation does not refresh the server snapshot after a save. */
export function navigateAfterEngineeringSave(target: string, browser: SaveNavigationBrowser = window) {
  const current = new URL(browser.location.href), destination = new URL(target, current);
  if (destination.origin === current.origin && destination.pathname === current.pathname && destination.search === current.search
    && (current.hash || destination.hash)) {
    browser.history.replaceState(browser.history.state, '', destination.href);
    browser.location.reload();
  } else browser.location.assign(target);
}

interface ReloadClick {
  defaultPrevented: boolean; button: number; ctrlKey: boolean; metaKey: boolean; shiftKey: boolean; altKey: boolean;
  preventDefault: () => void;
}

/** Modified clicks retain the browser's open-in-new-tab/window behavior. */
export function handleEngineeringReload(event: ReloadClick, target: string, browser: SaveNavigationBrowser = window) {
  if (event.defaultPrevented || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  navigateAfterEngineeringSave(target, browser);
}
