/******************************************************************************
 *
 * Copyright (C) 1997-2014 by Dimitri van Heesch.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation under the terms of the GNU General Public License is hereby 
 * granted. No representations are made about the suitability of this software 
 * for any purpose. It is provided "as is" without express or implied warranty.
 * See the GNU General Public License for more details.
 *
 * Documents produced by Doxygen are derivative works derived from the
 * input used in their production; they are not affected by this license.
 *
 */

%option never-interactive
%option prefix="sqlcodeYY"

%{

#include <stdio.h>

#include "sqlcode.h"

#include "entry.h"
#include "doxygen.h"
#include "outputlist.h"
#include "util.h"
#include "membername.h"
#include "searchindex.h"
#include "config.h"
#include "filedef.h"
#include "tooltip.h"

#define YY_NEVER_INTERACTIVE 1
#define YY_NO_INPUT 1
#define YY_NO_UNISTD_H 1

static CodeOutputInterface * g_code;
static QCString      g_curClassName;
static QCString      g_parmType;
static QCString      g_parmName;
static const char *  g_inputString;     //!< the code fragment as text
static int           g_inputPosition;   //!< read offset during parsing 
static int           g_inputLines;      //!< number of line in the code fragment
static int           g_yyLineNr;        //!< current line number
static bool          g_needsTermination;
static Definition   *g_searchCtx;

static bool          g_exampleBlock;
static QCString      g_exampleName;
static QCString      g_exampleFile;

static QCString      g_type;
static QCString      g_name;
static QCString      g_args;
static QCString      g_classScope;
   
static QCString      g_CurrScope;
   
static FileDef *     g_sourceFileDef;
static Definition *  g_currentDefinition;
static MemberDef *   g_currentMemberDef;
static bool          g_includeCodeFragment;
static const char *  g_currentFontClass;

static void codify(const char* text) 
{ 
  g_code->codify(text);
}

static void setCurrentDoc(const QCString &anchor)
{
  if (Doxygen::searchIndex)
  {
    if (g_searchCtx)
    {
      Doxygen::searchIndex->setCurrentDoc(g_searchCtx,g_searchCtx->anchor(),FALSE);
    }
    else
    {
      Doxygen::searchIndex->setCurrentDoc(g_sourceFileDef,anchor,TRUE);
    }
  }
}

/*! start a new line of code, inserting a line number if g_sourceFileDef
 * is TRUE. If a definition starts at the current line, then the line
 * number is linked to the documentation of that definition.
 */
static void startCodeLine()
{
  if (g_sourceFileDef)
  {   
    Definition *d   = g_sourceFileDef->getSourceDefinition(g_yyLineNr);
    
    if (!g_includeCodeFragment && d && d->isLinkableInProject())
    {
      g_currentDefinition = d;
      g_currentMemberDef = g_sourceFileDef->getSourceMember(g_yyLineNr);
      g_classScope = d->name().copy();
      QCString lineAnchor;
      lineAnchor.sprintf("l%05d",g_yyLineNr);
      if (g_currentMemberDef)
      {
        g_code->writeLineNumber(g_currentMemberDef->getReference(),
                            g_currentMemberDef->getOutputFileBase(),
                            g_currentMemberDef->anchor(),g_yyLineNr);
        setCurrentDoc(lineAnchor);
      }
      else
      {
        g_code->writeLineNumber(d->getReference(),
                            d->getOutputFileBase(),
                            0,g_yyLineNr);
        setCurrentDoc(lineAnchor);
      }
    }
    else
    {
      g_code->writeLineNumber(0,0,0,g_yyLineNr);
    }
  }
  
  g_code->startCodeLine(g_sourceFileDef);
  
  if (g_currentFontClass)
  {
    g_code->startFontClass(g_currentFontClass);
  }
}

static void endFontClass()
{
  if (g_currentFontClass)
  {
    g_code->endFontClass();
    g_currentFontClass=0;
  }
}

static void endCodeLine()
{
  endFontClass();
  g_code->endCodeLine();
}

static void nextCodeLine()
{
  const char *fc = g_currentFontClass;
  endCodeLine();
  if (g_yyLineNr<g_inputLines) 
  {
    g_currentFontClass = fc;
    startCodeLine();
  }
}

static void codifyLines(char *text)
{
  char *p=text,*sp=p;
  char c;
  bool done=FALSE;
  
  while (!done)
  {
    sp=p;
    
    while ((c=*p++) && c!='\n') { }
    
    if (c=='\n')
    {
      g_yyLineNr++;
      *(p-1)='\0';
      g_code->codify(sp);
      nextCodeLine();
    }
    else
    {
      g_code->codify(sp);
      done=TRUE;
    }
  }
}

static void startFontClass(const char *s)
{
  endFontClass();
  g_code->startFontClass(s);
  g_currentFontClass=s;
}

/*! counts the number of lines in the input */
static int countLines()
{
  const char *p=g_inputString;
  char c;
  int count=1;
  while ((c=*p)) 
  { 
    p++ ; 
    if (c=='\n') count++;  
  }
  if (p>g_inputString && *(p-1)!='\n') 
  { // last line does not end with a \n, so we add an extra
    // line and explicitly terminate the line after parsing.
    count++, 
    g_needsTermination=TRUE; 
  } 
  return count;
}

#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) result=yyread(buf,max_size);

static int yyread(char *buf,int max_size)
{
  int c=0;
  while( c < max_size && g_inputString[g_inputPosition] )
  {
    *buf = g_inputString[g_inputPosition++] ;
    c++; buf++;
  }
  return c;
}

%}

nl              (\r\n|\r|\n)
ws              [ \t]+
idchar          [A-Za-z0-9\-_]+
keywords1       ("ADD"|"ALL"|"ALLOCATE"|"ALTER"|"AND"|"ANY"|"ARE"|"AS"|"ASENSITIVE"|"ASYMMETRIC"|"AT"|"ATOMIC"|"AUTHORIZATION"|"BETWEEN"|"BOTH"|"BY"|"CALL"|"CALLED"|"CASCADED"|"CAST")
keywords2       ("CHECK"|"CLOSE"|"COLLATE"|"COLUMN"|"COMMIT"|"CONNECT"|"CONSTRAINT"|"CONTINUE"|"CORRESPONDING"|"CREATE"|"CROSS"|"CUBE"|"CURRENT"|"CURRENT_DATE"|"CURRENT_DEFAULT_TRANSFORM_GROUP")
keywords3       ("CURRENT_PATH"|"CURRENT_ROLE"|"CURRENT_TIME"|"CURRENT_TIMESTAMP"|"CURRENT_TRANSFORM_GROUP_FOR_TYPE"|"CURRENT_USER")
keywords4       ("CURSOR"|"CYCLE"|"DAY"|"DEALLOCATE"|"DECLARE"|"DEFAULT"|"DELETE"|"DEREF"|"DESCRIBE"|"DETERMINISTIC"|"DISCONNECT"|"DISTINCT"|"DROP"|"DYNAMIC")
keywords5       ("EACH"|"ELEMENT"|"END-EXEC"|"ESCAPE"|"EXCEPT"|"EXEC"|"EXECUTE"|"EXISTS"|"EXTERNAL"|"FETCH"|"FILTER"|"FOR"|"FOREIGN"|"FREE"|"FROM"|"FULL"|"FUNCTION")
keywords6       ("GET"|"GLOBAL"|"GRANT"|"GROUP"|"GROUPING"|"HAVING"|"HOLD"|"HOUR"|"IDENTITY"|"IMMEDIATE"|"IN"|"INDICATOR"|"INNER"|"INOUT"|"INPUT"|"INSENSITIVE"|"INSERT"|"INTERSECT")
keywords7       ("INTERVAL"|"INTO"|"IS"|"ISOLATION"|"JOIN"|"LANGUAGE"|"LARGE"|"LATERAL"|"LEADING"|"LEFT"|"LIKE"|"LOCAL"|"LOCALTIME"|"LOCALTIMESTAMP"|"MATCH"|"MEMBER"|"MERGE"|"METHOD"|"MINUTE")
keywords8       ("MODIFIES"|"MODULE"|"MONTH"|"MULTISET"|"NATIONAL"|"NATURAL"|"NEW"|"NO"|"NONE"|"NOT"|"OF"|"OLD"|"ON"|"ONLY"|"OPEN"|"OR"|"ORDER"|"OUT"|"OUTER"|"OUTPUT")
keywords9       ("OVER"|"OVERLAPS"|"PARAMETER"|"PARTITION"|"PRECISION"|"PREPARE"|"PRIMARY"|"PROCEDURE"|"RANGE"|"READS"|"RECURSIVE"|"REF"|"REFERENCES"|"REFERENCING"|"REGR_AVGX"|"REGR_AVGY")
keywords10      ("REGR_COUNT"|"REGR_INTERCEPT"|"REGR_R2"|"REGR_SLOPE"|"REGR_SXX"|"REGR_SXY"|"REGR_SYY"|"RELEASE"|"RESULT"|"RETURN"|"RETURNS"|"REVOKE"|"RIGHT"|"ROLLBACK"|"ROLLUP"|"ROW"|"ROWS"|"SAVEPOINT")
keywords11      ("SCROLL"|"SEARCH"|"SECOND"|"SELECT"|"SENSITIVE"|"SESSION_USER"|"SET"|"SIMILAR"|"SOME"|"SPECIFIC"|"SPECIFICTYPE"|"SQL"|"SQLEXCEPTION"|"SQLSTATE"|"SQLWARNING"|"START"|"STATIC")
keywords12      ("SUBMULTISET"|"SYMMETRIC"|"SYSTEM"|"SYSTEM_USER"|"TABLE"|"THEN"|"TIMEZONE_HOUR"|"TIMEZONE_MINUTE"|"TO"|"TRAILING"|"TRANSLATION"|"TREAT"|"TRIGGER"|"UESCAPE"|"UNION")
keywords13      ("UNIQUE"|"UNNEST"|"UPDATE"|"UPPER"|"USER"|"USING"|"VALUE"|"VALUES"|"VAR_POP"|"VAR_SAMP"|"VARYING"|"WHEN"|"WHENEVER"|"WHERE"|"WIDTH_BUCKET"|"WINDOW"|"WITH"|"WITHIN"|"WITHOUT"|"YEAR")

/* Need multiple keyword definitions due to max length */
keyword         (?i:{keywords1}|{keywords2}|{keywords3}|{keywords4}|{keywords5}|{keywords6}|{keywords7}|{keywords8}|{keywords9}|{keywords10}|{keywords11}|{keywords12}|{keywords13})

typekeyword     (?i:"ARRAY"|"BIGINT"|"BINARY"|"BLOB"|"BOOLEAN"|"CHAR"|"CHARACTER"|"CLOB"|"DATE"|"DEC"|"DECIMAL"|"DOUBLE"|"FLOAT"|"INT"|"INTEGER"|"NCHAR"|"NCLOB"|"NUMERIC"|"NVARCHAR"|"REAL"|"SMALLINT"|"TIME"|"TIMESTAMP"|"VARCHAR")

flowkeyword     (?i:"CASE"|"IF"|"ELSE"|"BEGIN"|"END"|"WHILE")

literalkeyword  (?i:"FALSE"|"TRUE"|"NULL"|"UNKNOWN")
stringliteral   (\"[^"]*\")|('[^']*')
number          [0-9]+
literals        ({literalkeyword}|{stringliteral}|{number})

variable        @{idchar}+

simplecomment   --.*
commentopen     "/\*"
commentclose    "\*/"
 
%option noyywrap
%option nounput

%x COMMENT

%%

{literals}          {
                        startFontClass("stringliteral");
                        codifyLines(yytext);
                        endFontClass();
                    }
                

{keyword}           {
                        startFontClass("keyword");
                        codifyLines(yytext);
                        endFontClass();
                    }

{flowkeyword}       {
                        startFontClass("keywordflow");
                        codifyLines(yytext);
                        endFontClass();
                    }

{typekeyword}       {
                        startFontClass("keywordtype");
                        codifyLines(yytext);
                        endFontClass();
                    }

{variable}          {
                        startFontClass("preprocessor");
                        codifyLines(yytext);
                        endFontClass();
                    }

{simplecomment}     {
                        startFontClass("comment");
                        codifyLines(yytext);
                        endFontClass();
                    }

{commentopen}       {
                        startFontClass("comment");
                        codifyLines(yytext);
                        BEGIN(COMMENT);
                    }

<COMMENT>.          {
                        codifyLines(yytext);
                    }
<COMMENT>{nl}       {
                        codifyLines(yytext);
                    }

<COMMENT>{commentclose} {
                        codifyLines(yytext);
                        endFontClass();
                        BEGIN(INITIAL);
                    }
                    
{idchar}            {
                        codifyLines(yytext);
                    }

{nl}                {
                        codifyLines(yytext);
                    }

.                   {
                        codifyLines(yytext);
                    }

%%

void parseSqlCode(
    CodeOutputInterface &od,
    const char * /*className*/,
    const QCString &s,
    bool exBlock,
    const char *exName,
    FileDef *fd,
    int startLine,
    int endLine,
    bool inlineFragment,
    MemberDef *,
    bool,Definition *searchCtx,
    bool /*collectXRefs*/
    ) 
{  
  if (s.isEmpty()) return;
  
  g_code = &od;
  g_inputString   = s;
  g_inputPosition = 0;
  g_currentFontClass = 0;
  g_needsTermination = FALSE;
  g_searchCtx=searchCtx;
  
  if (startLine!=-1)
    g_yyLineNr    = startLine;
  else
    g_yyLineNr    = 1;
  
  if (endLine!=-1)
    g_inputLines  = endLine+1;
  else
    g_inputLines  = g_yyLineNr + countLines() - 1;
  
  g_exampleBlock  = exBlock; 
  g_exampleName   = exName;
  g_sourceFileDef = fd;

  bool cleanupSourceDef = FALSE;
  
  if (exBlock && fd==0)
  {
    // create a dummy filedef for the example
    g_sourceFileDef = new FileDef("",(exName?exName:"generated"));
    cleanupSourceDef = TRUE;
  }
  
  if (g_sourceFileDef) 
  {
    setCurrentDoc("l00001");
  }

  g_includeCodeFragment = inlineFragment;
  // Starts line 1 on the output  
  startCodeLine();

  sqlcodeYYrestart( sqlcodeYYin );

  sqlcodeYYlex();

  if (g_needsTermination)
  {
    endCodeLine();
  }
  if (cleanupSourceDef)
  {
    // delete the temporary file definition used for this example
    delete g_sourceFileDef;
    g_sourceFileDef=0;
  }
  
  return;
}

void resetSqlCodeParserState() 
{
  g_currentDefinition = 0;
  g_currentMemberDef = 0;
}

#if !defined(YY_FLEX_SUBMINOR_VERSION) 
extern "C" { // some bogus code to keep the compiler happy
  void sqlcodeYYdummy() { yy_flex_realloc(0,0); } 
}
#elif YY_FLEX_MAJOR_VERSION<=2 && YY_FLEX_MINOR_VERSION<=5 && YY_FLEX_SUBMINOR_VERSION<33
#error "You seem to be using a version of flex newer than 2.5.4. These are currently incompatible with 2.5.4, and do NOT work with doxygen! Please use version 2.5.4 or expect things to be parsed wrongly! A bug report has been submitted (#732132)."
#endif

