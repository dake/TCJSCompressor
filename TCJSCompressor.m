//
//  TCJSCompressor.m
//  TCKit
//
//  Created by dake on 16/5/26.
//  Copyright © 2016年 dake. All rights reserved.
//

#import "TCJSCompressor.h"

@implementation TCJSCompressor
{
@private
    int _theA;
    int _theB;
    int _theLookahead;
    int _theX;
    int _theY;
    
    FILE *_in;
    FILE *_out;
}

- (void)dealloc
{
    if (NULL != _in) {
        fclose(_in);
    }
    
    if (NULL != _out) {
        fclose(_out);
    }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _theLookahead = EOF;
        _theX = EOF;
        _theY = EOF;
    }
    return self;
}

+ (BOOL)compressFile:(NSString *)inPath to:(NSString *)outPath error:(NSError **)err
{
    NSParameterAssert(inPath);
    NSParameterAssert(outPath);
    
    FILE *fileIn = fopen(inPath.UTF8String, "r");
    FILE *fileOut = fopen(outPath.UTF8String, "w");
    if (NULL != fileIn && NULL != fileOut) {
        TCJSCompressor *core = [[TCJSCompressor alloc] init];
        core->_in = fileIn;
        core->_out = fileOut;
        return jsmin(core, err);
    }
    
    if (NULL != fileIn) {
        fclose(fileIn);
    }
    
    if (NULL != fileOut) {
        fclose(fileOut);
    }
    
    if (NULL != err) {
        NSError *error = [NSError errorWithDomain:NSStringFromClass(self)
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"file path invalid."}];
        *err = error;
    }
    
    return NO;
}


/* isAlphanum -- return true if the character is a letter, digit, underscore,
 dollar sign, or non-ASCII character.
 */

static BOOL isAlphanum(int c)
{
    return ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            (c >= 'A' && c <= 'Z') || c == '_' || c == '$' || c == '\\' ||
            c > 126);
}


/* get -- return the next character from stdin. Watch out for lookahead. If
 the character is a control character, translate it to a space or
 linefeed.
 */

static int get(TCJSCompressor *core)
{
    int c = core->_theLookahead;
    core->_theLookahead = EOF;
    if (c == EOF) {
        c = getc(core->_in);
    }
    if (c >= ' ' || c == '\n' || c == EOF) {
        return c;
    }
    if (c == '\r') {
        return '\n';
    }
    return ' ';
}


/* peek -- get the next character without getting it.
 */

static int peek(TCJSCompressor *core)
{
    core->_theLookahead = get(core);
    return core->_theLookahead;
}


/* next -- get the next character, excluding comments. peek() is used to see
 if a '/' is followed by a '/' or '*'.
 */

static int next(TCJSCompressor *core, NSError **err)
{
    int c = get(core);
    if  (c == '/') {
        switch (peek(core)) {
            case '/':
                for (;;) {
                    c = get(core);
                    if (c <= '\n') {
                        break;
                    }
                }
                break;
            case '*':
                get(core);
                while (c != ' ') {
                    switch (get(core)) {
                        case '*':
                            if (peek(core) == '/') {
                                get(core);
                                c = ' ';
                            }
                            break;
                        case EOF:
                            if (NULL != err) {
                                NSError *error = [NSError errorWithDomain:NSStringFromClass(core.class)
                                                                     code:-1
                                                                 userInfo:@{NSLocalizedDescriptionKey: @"Unterminated comment."}];
                                *err = error;
                            }
                            return c;
                    }
                }
                break;
        }
    }
    core->_theY = core->_theX;
    core->_theX = c;
    return c;
}


/* action -- do something! What you do is determined by the argument:
 1   Output A. Copy B to A. Get the next B.
 2   Copy B to A. Get the next B. (Delete A).
 3   Get the next B. (Delete B).
 action treats a string as a single character. Wow!
 action recognizes a regular expression if it is preceded by ( or , or =.
 */

static BOOL action(int d, TCJSCompressor *core, NSError **err)
{
    switch (d) {
        case 1: {
            
            int theA = core->_theA;
            int theB = core->_theB;
            if (theA != '\0') {
                putc(theA, core->_out);
            }
            
            int theY = core->_theY;
            if (
                (theY == '\n' || theY == ' ') &&
                (theA == '+' || theA == '-' || theA == '*' || theA == '/') &&
                (theB == '+' || theB == '-' || theB == '*' || theB == '/')
                ) {
                putc(core->_theY, core->_out);
            }
        }
            
        case 2: {
            int theA = core->_theB;
            core->_theA = theA;
            
            if (theA == '\'' || theA == '"' || theA == '`') {
                for (;;) {
                    putc(theA, core->_out);
                    theA = get(core);
                    core->_theA = theA;
                    if (theA == core->_theB) {
                        break;
                    }
                    if (theA == '\\') {
                        putc(theA, core->_out);
                        theA = get(core);
                        core->_theA = theA;
                    }
                    if (theA == EOF) {
                        if (NULL != err) {
                            NSError *error = [NSError errorWithDomain:NSStringFromClass(core.class)
                                                                 code:-1
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Unterminated string literal."}];
                            *err = error;
                        }
                        return NO;
                    }
                }
            }
        }
            
        case 3: {
            int theA = core->_theA;
            NSError *error = nil;
            int theB = next(core, &error);
            if (nil != error) {
                if (NULL != err) {
                    *err = error;
                }
                return NO;
            }
            core->_theB = theB;
            
            if (theB == '/' && (
                                theA == '(' || theA == ',' || theA == '=' || theA == ':' ||
                                theA == '[' || theA == '!' || theA == '&' || theA == '|' ||
                                theA == '?' || theA == '+' || theA == '-' || theA == '~' ||
                                theA == '*' || theA == '/' || theA == '{' || theA == '\n'
                                )) {
                putc(theA, core->_out);
                if (theA == '/' || theA == '*') {
                    putc(' ', core->_out);
                }
                putc(theB, core->_out);
                for (;;) {
                    theA = get(core);
                    core->_theA = theA;
                    if (theA == '[') {
                        for (;;) {
                            putc(theA, core->_out);
                            theA = get(core);
                            core->_theA = theA;
                            if (theA == ']') {
                                break;
                            }
                            if (theA == '\\') {
                                putc(theA, core->_out);
                                theA = get(core);
                                core->_theA = theA;
                            }
                            if (theA == EOF) {
                                if (NULL != err) {
                                    NSError *error = [NSError errorWithDomain:NSStringFromClass(core.class)
                                                                         code:-1
                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Unterminated set in Regular Expression literal."}];
                                    *err = error;
                                }
                                return NO;
                            }
                        }
                    } else if (theA == '/') {
                        switch (peek(core)) {
                            case '/':
                            case '*':
                                if (NULL != err) {
                                    NSError *error = [NSError errorWithDomain:NSStringFromClass(core.class)
                                                                         code:-1
                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Unterminated set in Regular Expression literal."}];
                                    *err = error;
                                }
                                return NO;
                        }
                        break;
                    } else if (theA =='\\') {
                        putc(theA, core->_out);
                        theA = get(core);
                        core->_theA = theA;
                    }
                    
                    if (theA == EOF) {
                        if (NULL != err) {
                            NSError *error = [NSError errorWithDomain:NSStringFromClass(core.class)
                                                                 code:-1
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Unterminated Regular Expression literal."}];
                            *err = error;
                        }
                        return NO;
                    }
                    putc(theA, core->_out);
                }
                
                NSError *error = nil;
                core->_theB = next(core, &error);
                if (nil != error) {
                    if (NULL != err) {
                        *err = error;
                    }
                    return NO;
                }
            }
        } // case 3
    }
    
    return YES;
}


/* jsmin -- Copy the input to the output, deleting the characters which are
 insignificant to JavaScript. Comments will be removed. Tabs will be
 replaced with spaces. Carriage returns will be replaced with linefeeds.
 Most spaces and linefeeds will be removed.
 */

static BOOL jsmin(TCJSCompressor *core, NSError **err)
{
    NSCParameterAssert(core->_in);
    NSCParameterAssert(core->_out);
    
    if (peek(core) == 0xEF) {
        get(core);
        get(core);
        get(core);
    }
    
    core->_theA = '\0'; // '\n'
    if (!action(3, core, err)) {
        return NO;
    }
    
    while (core->_theA != EOF) {
        switch (core->_theA) {
            case ' ':
                if (!action(isAlphanum(core->_theB) ? 1 : 2, core, err)) {
                    return NO;
                }
                break;
                
            case '\n':
                switch (core->_theB) {
                    case '{':
                    case '[':
                    case '(':
                    case '+':
                    case '-':
                    case '!':
                    case '~':
                        if (!action(1, core, err)) {
                            return NO;
                        }
                        break;
                    case ' ':
                        if (!action(3, core, err)) {
                            return NO;
                        }
                        break;
                    default:
                        if (!action(isAlphanum(core->_theB) ? 1 : 2, core, err)) {
                            return NO;
                        }
                        break;
                }
                break;
                
            default:
                switch (core->_theB) {
                    case ' ':
                        if (!action(isAlphanum(core->_theA) ? 1 : 3, core, err)) {
                            return NO;
                        }
                        break;
                        
                    case '\n':
                        switch (core->_theA) {
                            case '}':
                            case ']':
                            case ')':
                            case '+':
                            case '-':
                            case '"':
                            case '\'':
                            case '`':
                                if (!action(1, core, err)) {
                                    return NO;
                                }
                                break;
                            default:
                                if (!action(isAlphanum(core->_theA) ? 1 : 3, core, err)) {
                                    return NO;
                                }
                                break;
                        }
                        break;
                        
                    default:
                        if (!action(1, core, err)) {
                            return NO;
                        }
                        break;
                }
                break;
        }
    }
    
    return YES;
}

@end