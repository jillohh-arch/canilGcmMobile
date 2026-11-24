import * as assert from "node:assert/strict";
import {test} from "node:test";
import {evaluateK9AssociationInTransaction, ShiftActor, ShiftTxn} from "../shift_authorization_engine";
const actor: ShiftActor={uid:"u",ra:"r",email:"r@x",name:"R"};
function tx(): ShiftTxn{return {get:async(p)=>({exists:p.startsWith("dogs/"),data:{}}),getCollection:async()=>({kind:"docs",docs:[]}),set:()=>{}};}
test("K9 guard allows trusted actor with current evidence",async()=>{const d=await evaluateK9AssociationInTransaction({transaction:tx(),trustedActor:actor,dogId:"d",associationIntent:"K9_ASSOCIATION_REQUESTED",currentAuthorityEvidence:{actorUid:"u",actorRa:"r",dogId:"d"}}); assert.equal(d.status,"ALLOWED");});
test("K9 guard fails closed without trusted evidence",async()=>{const d=await evaluateK9AssociationInTransaction({transaction:tx(),trustedActor:actor,dogId:"d",associationIntent:"K9_ASSOCIATION_REQUESTED"}); assert.equal(d.status,"UNKNOWN");});
test("no K9 intent is neutral",async()=>{const d=await evaluateK9AssociationInTransaction({transaction:tx(),trustedActor:null,associationIntent:"NO_K9_ASSOCIATION"}); assert.equal(d.status,"ALLOWED");});
