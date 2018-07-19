# Fuzzel

*author:* https://gmod.facepunch.com/u/htgr/Apickx/  
*original:* https://gmod.facepunch.com/f/gmoddev/nwdd/Fuzzel-lua-Fuzzy-string-matching-Never-write-concommand-autocomplete-code-again/1/

Hello everyone, long time lurker, first time starting a thread.

I got annoyed while jumping around the code for various projects. I wouldn't remember how options for console commands are formatted, so I would write an autocomplete, after re-writing it twice I got tired, and decided to put an end to it.

I'll try to anticipate some of the questions you might have:

**What the fuck is this?**

It's a collection of functions for fuzzy string matching, that is, it can find the edit distance between two strings.

There are several kinds of edit distance

[Hamming distance](https://en.wikipedia.org/wiki/Hamming_distance) is the number of substitutions it takes to get from one string to another. It can only be calculated on two strings of the same length. For example: the hamming distance between "Lazure Hat" and "Lulzey Cat" is 6

[Levenshtein Distance](https://en.wikipedia.org/wiki/Levenshtein_distance) is the number of insertions, deletions or substitutions it takes to transform one string into another. For example: "test" to "toast" will take 2 (substitute o for e in test, then insert a)

[Damerau-Levenshtein Distance](https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance) is exactly like above, only it adds transposition--

**Holy shit I don't care, give me code.**

Well, fuzzel was written especially to be minified, just over 2kb!

``` lua
--This code has been minified! Original at cogarr.net/source/cgit.cgi/fuzzel
local a,b,c,d,e,f,g,h,i,j,k,l,m=string.len,string.byte,math.min,assert,pairs,ipairs,type,unpack,table.insert,table.sort,string.sub,true,false;local n={}local o,p,q,r,s,t,u,v,w,x="Damerau","Levenshtein","Distance","Ratio","Fuzzy","Find","Sort","_extended","Hamming","Autocomplete"local y,z,A,B,C,D,E,F,G,H,I,J,K,L=p..q..v,p..q,p..r,o..p..q..v,o..p..q,o..p..r,s..t..q,s..t..r,s..u..q,s..u..r,w..q,w..r,s..x..q,s..x..r;local function M(N,O,P,Q,R,...)local S={...}local T,U=a(N),a(O)local V={}for W=0,T do V[W]={}for X=0,U do V[W][X]=0 end end;for W=1,T do V[W][0]=W end;for X=1,U do V[0][X]=X end;for X=1,U do for W=1,T do local Y,Z=b(N,W),b(O,X)V[W][X]=c(V[W-1][X]+R,V[W][X-1]+P,V[W-1][X-1]+(Y==Z and 0 or Q))if S[1]and W>1 and X>1 and Y==b(O,X-1)and b(N,W-1)==Z then V[W][X]=c(V[W][X],V[W-2][X-2]+(Y==Z and 0 or S[2]))end end end;return V[T][U]end;n[y]=function(N,O,P,Q,R)return M(N,O,P,Q,R)end;n.ld_e=n[y]n[z]=function(N,O)return n.ld_e(N,O,1,1,1)end;n.ld=n[z]n[A]=function(N,O)return n.ld(N,O)/a(N)end;n.lr=n[A]n[B]=function(N,O,P,Q,R,_)return M(N,O,P,Q,R,l,_)end;n.dld_e=n[B]n[C]=function(N,O)return n.dld_e(N,O,1,1,1,1)end;n.dld=n[C]n[D]=function(N,O)return n.dld(N,O)/a(N)end;n.dlr=n[D]n[I]=function(N,O)local a0,a1=a(N),0;d(a0==a(O),w.." "..q.." cannot be calculated on two strings of different lengths:\""..N.."\" \""..O.."\"")for W=1,a0 do a1=a1+(b(N,W)~=b(O,W)and 1 or 0)end;return a1 end;n.hd=n[I]n[J]=function(N,O)return n.hd(N,O)/a(N)end;n.hr=n[J]local function a2(a3,a4,...)local S={...}local a5=g(S[1])=="table"and S[1]or S;local a6,a7=a4(a5[1],a3),a5[1]for a8,a9 in e(a5)do local aa=a4(a9,a3)if aa<=a6 then a6,a7=aa,a8 end end;return a5[a7],a6 end;n[E]=function(a3,...)return h{a2(a3,n.dld,...)}end;n.ffd=n[E]n[F]=function(a3,...)return h{a2(a3,n.dlr,...)}end;local function ab(a3,a4,ac,...)local S={...}local a5=g(S[1])=="table"and S[1]or S;local ad,ae,af,ag={},{},{},a(a3)for a8,a9 in e(a5)do local ah=ac and k(a9,0,ag)or a9;local a1=a4(a3,ah)if ad[a1]==nil then ad[a1]={}i(ae,a1)end;i(ad[a1],a9)end;j(ae)for a8,a9 in f(ae)do for W,X in e(ad[a9])do i(af,X)end end;return af end;n.ffr=n[F]n[G]=function(a3,...)return ab(a3,n.dld,m,...)end;n.fsd=n[G]n[H]=function(a3,...)return ab(a3,n.dlr,m,...)end;n.fsr=n[H]n[K]=function(a3,...)return ab(a3,n.dld,l,...)end;n.fad=n[K]n[L]=function(a3,...)return ab(a3,n.dlr,l,...)end;n.far=n[L]return n
```

**Hey that code didn't work, moron.**

Oh, well you have to use it as part of your addon, for example, here's how you would write an auto-complete function:

``` lua
local fuzzel = include("fuzzel.lua")

local function printstuff(ply,cmd,args)
    PrintTable(args)
end

local function autocompletefunction(...)
    local opt = {...}
    opt = type(opt[1]) == "table" and opt[1] or opt
    return function(cmd,strargs)
        --Remove spaces and quotes, since we don't want to match them
        strargs = string.gsub(strargs,"[\" ]","")
        --Find the options that most closely resemble our command so far
        local sorted = fuzzel.fad(strargs,opt)
        --Add quotes if needed, and preppend the command to each option
        for k,v in pairs(sorted) do
            if string.find(v," ") ~= nil then
                sorted[k]="\""..v.."\""
            end
            sorted[k]=cmd.." "..sorted[k]
        end
        return sorted
    end
end

local options = {
    "discover",
    "dispersion",
    "hedge",
    "power spaces",
    "multiply",
    "psychic",
    "shortness",
    "telescope",
    ">?xQuirky&*",
}
concommand.Add("TestConCommand",printstuff,autocompletefunction(options),"help text")

concommand.Add("AnotherCommand",printstuff,autocompletefunction("You","Can","Even","Use","It","Like","This"),"Help text")
```
Ta-da!

**Oh, that's cool. I guess.**

Yeah! Let me tell you about what else it can do! Taken straight from the un-minified file:

``` lua
-- Calculates the Levenshtein Distance between two strings, useing the costs given. "Real" Levenshtein Distance uses values 1,1,1 for costs.
-- returns number_distance
fuzzel.LevenshteinDistance_extended(string_first, string_second, number_addcost, number_substituecost, number_deletecost)

-- Calculates the "real" Levenshtein Distance
-- returns number_distance
fuzzel.LevenshteinDistance(string_first, strings_second)

-- The Levenshtein Ratio divided by the first string's length. Useing a ratio is a decent way to determin if a spelling is "close enough"
-- returns number_distance
fuzzel.LevensteinRatio(string_first, string_second)

-- Damerau-Levenshtein Distance is almost exactly like Levenshtein Distance, with the caveat that two letters next to each other, with swapped positions only counts as "one" cost (in "real" Damerau-Levenshtein Distance)
-- returns number
fuzzel.DamerauLevenshteinDistance_extended(string_first, string_second, number_addcost, number_substituecost, number_deletecost, number_transpositioncost)

-- Calculates the "real" Damerau-Levenshtein Distance
-- returns number
fuzzel.DamerauLevenshteinDistance(stirng_first, strings_second)

-- The Damerau-Levenshtein Distance divided by the first string's length
-- returns number_ratio
fuzzel.DamerauLevenshteinRatio(string_first, string_second)

-- Purely the number of substitutions needed to change one string into another. Note that both
-- strings must be the same length.
-- returns number_distance
fuzzel.HammingDistance(string_first, string_second)

-- The hamming distance divided by the length of the first string
-- returns number_ratio
fuzzel.HammingRatio(string_first, string_second)

-- in may be either a table, or a list of arguments. fuzzel.FuzzyFindDistance will find the string that most closely resembles needle, based on Damerau-Levenshtein Distance. If multiple options have the same distance, it will return the first one encountered (This may not be in any sort of order!)
-- returns string_closest, number_distance
fuzzel.FuzzyFindDistance(string_needle, vararg_in)

-- in may be either a table, or a list of arguments. Same as above, except it returns the string with the closest Damerau-Levenshtein ratio.
-- returns string_closest, nubmer_ratio
fuzzel.FuzzyFindRatio(string_needle, vararg_in)

-- Sorts either the table, or the arguments, and returns a table. Uses Damerau-Levenshtein Distanc
fuzzel.FuzzySortDistance(string_needle, vararg_in)
```
