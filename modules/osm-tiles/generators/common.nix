{lib}: let
  sanitizeLocale = locale:
    lib.replaceStrings ["-" ":" "."] ["_" "_" "_"] (lib.toLower locale);

  localeColumn = locale: "name_${sanitizeLocale locale}";

  quoteSqlLiteral = value: "'${lib.replaceStrings ["'"] ["''"] value}'";

  quoteIdent = ident: "\"${lib.replaceStrings ["\""] ["\"\""] ident}\"";
in {
  inherit
    localeColumn
    quoteIdent
    quoteSqlLiteral
    sanitizeLocale
    ;

  localeColumns = locales: map localeColumn locales;

  localeJsonExprs = {
    alias,
    locales,
  }:
    map (locale: "${alias}.names ->> ${quoteSqlLiteral locale} AS ${localeColumn locale}") locales;

  localeNullExprs = locales: map (locale: "NULL::text AS ${localeColumn locale}") locales;

  sqlColumnList = cols: lib.concatStringsSep ",\n    " cols;

  unionSql = statements:
    if statements == []
    then null
    else lib.concatStringsSep "\nUNION ALL\n" statements;
}
