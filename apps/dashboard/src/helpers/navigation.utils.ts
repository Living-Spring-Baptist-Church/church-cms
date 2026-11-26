import { ROUTES } from "@core/data/routes.data";

/** A module is current when the path is its route or sits under it. Home matches only itself. */
export function isRouteActive(pathname: string, href: string): boolean {
  if (pathname === href) {
    return true;
  }
  return href !== ROUTES.home && pathname.startsWith(`${href}/`);
}
