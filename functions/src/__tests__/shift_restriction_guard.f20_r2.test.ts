import * as assert from "node:assert/strict";
import {test} from "node:test";
import {evaluateShiftRestrictionGuard} from "../shift_restriction_guard";
test("malformed query is unavailable",()=>{const d=evaluateShiftRestrictionGuard({restrictions:{kind:"failed",reasonCode:"x"},now:new Date()}); assert.equal(d.outcome,"unavailable");});
test("active absolute restriction denies",()=>{const d=evaluateShiftRestrictionGuard({restrictions:{kind:"docs",docs:[{id:"r",data:{status:"active",level:"absolute",category:"x",description:"x",activities_restricted:[],since:new Date().toISOString()}}]},now:new Date()}); assert.equal(d.outcome,"blocked_absolute");});
