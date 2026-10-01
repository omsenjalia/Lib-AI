// sql.js ships its asm.js build as a separate entry with no types of its own;
// it exposes the same API as the main package.
declare module 'sql.js/dist/sql-asm.js' {
  import initSqlJs from 'sql.js';
  export default initSqlJs;
}
