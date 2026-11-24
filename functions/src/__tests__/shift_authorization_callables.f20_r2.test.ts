import * as assert from "node:assert/strict";
import {test} from "node:test";
import {actorBoundFingerprint, ShiftActor} from "../shift_authorization_engine";
const a:ShiftActor={uid:"u",ra:"r",email:"e",name:"n"};
test("actor bound fingerprint changes with actor",()=>{const i:any={action:"start_shift",dogId:"d",operationId:"o"}; assert.notEqual(actorBoundFingerprint(a,i),actorBoundFingerprint({...a,uid:"other"},i));});
test("context is material",()=>{const i:any={action:"start_shift",dogId:"d",operationId:"o",sessionId:"s"}; assert.notEqual(actorBoundFingerprint(a,i),actorBoundFingerprint(a,{...i,sessionId:"s2"}));});
