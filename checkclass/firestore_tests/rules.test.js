const fs = require('node:fs');
const { test, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, getDocs, collection, updateDoc, writeBatch, serverTimestamp,
} = require('firebase/firestore');

const CODE = 'ABC234';
const SESSION = `sessions/${CODE}`;
const Q1 = `${SESSION}/questions/q1`;
const Q2 = `${SESSION}/questions/q2`;
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-checkclass',
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

// Ausgangslage: Session läuft, q1 ist die aktuelle Frage und bereits "open".
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, SESSION), {
      teacherId: 'teacher', question: 'Alles verstanden?',
      currentQuestionId: 'q1', active: true, createdAt: new Date(),
    });
    await setDoc(doc(db, Q1), { text: 'Alles verstanden?', status: 'open', createdAt: new Date() });
    await setDoc(doc(db, `${Q1}/votes/other`), { answer: 'no', createdAt: new Date() });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const vote = (answer = 'yes') => ({ answer, createdAt: serverTimestamp() });
const setStatus = (path, status) =>
  env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), path), { status }));

// ------------------------------------------------------------ Abstimmungsablauf

test('1. Beitreten vor dem Start ist möglich', async () => {
  await setStatus(Q1, 'prepared');
  await assertSucceeds(setDoc(doc(as('s1'), `${SESSION}/participants/s1`), { joinedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(as('s1'), SESSION)));
  await assertSucceeds(getDoc(doc(as('s1'), Q1)));
});

test('2. Abstimmen vor dem Start wird abgelehnt', async () => {
  await setStatus(Q1, 'prepared');
  await assertFails(setDoc(doc(as('s1'), `${Q1}/votes/s1`), vote()));
});

test('3. Abstimmen nach dem Start ist erlaubt (Lehrkraft öffnet, Schüler stimmen ab)', async () => {
  await setStatus(Q1, 'prepared');
  await assertSucceeds(updateDoc(doc(as('teacher'), Q1), { status: 'open' }));
  await assertSucceeds(setDoc(doc(as('s1'), `${Q1}/votes/s1`), vote('yes')));
  // Spätbeitretende können ebenfalls abstimmen
  await assertSucceeds(setDoc(doc(as('late'), `${SESSION}/participants/late`), { joinedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(as('late'), `${Q1}/votes/late`), vote('no')));
});

test('4. Abstimmen nach dem Ende wird abgelehnt, Stimmen bleiben lesbar', async () => {
  await assertSucceeds(setDoc(doc(as('s1'), `${Q1}/votes/s1`), vote()));
  await assertSucceeds(updateDoc(doc(as('teacher'), Q1), { status: 'closed' }));
  await assertFails(setDoc(doc(as('s2'), `${Q1}/votes/s2`), vote()));
  await assertSucceeds(getDoc(doc(as('teacher'), `${Q1}/votes/s1`)));
  await assertSucceeds(getDoc(doc(as('s1'), `${Q1}/votes/s1`)));
});

test('5. Neue Frage startet zunächst geschlossen (prepared), alte wird beendet', async () => {
  const t = as('teacher');
  // Direkt als "open" anlegen ist verboten
  await assertFails(setDoc(doc(t, Q2), { text: 'Zweite', status: 'open', createdAt: serverTimestamp() }));

  // Vorbereiten wie in der App: alte schließen + neue anlegen + Session umstellen (ein Batch)
  const batch = writeBatch(t);
  batch.update(doc(t, Q1), { status: 'closed' });
  batch.set(doc(t, Q2), { text: 'Zweite', status: 'prepared', createdAt: serverTimestamp() });
  batch.update(doc(t, SESSION), { question: 'Zweite', currentQuestionId: 'q2' });
  await assertSucceeds(batch.commit());

  await assertFails(setDoc(doc(as('s1'), `${Q2}/votes/s1`), vote()));
  await assertFails(setDoc(doc(as('s1'), `${Q1}/votes/s1`), vote()));
});

test('6. Neue Frage starten: Abstimmung wieder möglich, eine Stimme pro Frage bleibt', async () => {
  await assertSucceeds(setDoc(doc(as('s1'), `${Q1}/votes/s1`), vote('yes')));

  const t = as('teacher');
  const batch = writeBatch(t);
  batch.update(doc(t, Q1), { status: 'closed' });
  batch.set(doc(t, Q2), { text: 'Zweite', status: 'prepared', createdAt: serverTimestamp() });
  batch.update(doc(t, SESSION), { question: 'Zweite', currentQuestionId: 'q2' });
  await batch.commit();

  await assertSucceeds(updateDoc(doc(as('teacher'), Q2), { status: 'open' }));
  await assertSucceeds(setDoc(doc(as('s1'), `${Q2}/votes/s1`), vote('no')));
  await assertFails(setDoc(doc(as('s1'), `${Q2}/votes/s1`), vote('yes')));
});

// ------------------------------------------------------------- Status-Übergänge

test('Status nur vorwärts: geschlossene Fragen bleiben geschlossen', async () => {
  await setStatus(Q1, 'closed');
  await assertFails(updateDoc(doc(as('teacher'), Q1), { status: 'open' }));
  await assertFails(updateDoc(doc(as('teacher'), Q1), { status: 'prepared' }));
});

test('nur die aktuelle Frage einer laufenden Session darf geöffnet werden', async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), Q2), { text: 'Alt', status: 'prepared', createdAt: new Date() }));
  await assertFails(updateDoc(doc(as('teacher'), Q2), { status: 'open' })); // q2 ist nicht aktuell

  await setStatus(Q1, 'prepared');
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), SESSION), { active: false }));
  await assertFails(updateDoc(doc(as('teacher'), Q1), { status: 'open' })); // Session beendet
});

test('Schüler können weder Status noch Text ändern, die Lehrkraft nur den Status', async () => {
  await assertFails(updateDoc(doc(as('s1'), Q1), { status: 'closed' }));
  await assertFails(updateDoc(doc(as('s1'), SESSION), { active: false }));
  await assertFails(updateDoc(doc(as('teacher'), Q1), { text: 'Manipuliert' }));
  await assertFails(updateDoc(doc(as('teacher'), SESSION), { teacherId: 'someoneElse' }));
});

// --------------------------------------------------------------- Stimmen-Regeln

test('genau eine eigene Stimme pro Frage, kein Überschreiben', async () => {
  const db = as('s1');
  await assertSucceeds(setDoc(doc(db, `${Q1}/votes/s1`), vote('yes')));
  await assertFails(setDoc(doc(db, `${Q1}/votes/s1`), vote('no')));
  await assertFails(updateDoc(doc(db, `${Q1}/votes/s1`), { answer: 'no' }));
});

test('keine Stimme im Namen anderer, keine ungültigen Werte oder Zusatzfelder', async () => {
  const db = as('s1');
  await assertFails(setDoc(doc(db, `${Q1}/votes/s2`), vote()));
  await assertFails(setDoc(doc(db, `${Q1}/votes/s1`), vote('maybe')));
  await assertFails(setDoc(doc(db, `${Q1}/votes/s1`), { answer: 'yes', createdAt: serverTimestamp(), extra: 1 }));
});

test('Schüler lesen nur die eigene Stimme, die Lehrkraft alle', async () => {
  await assertFails(getDoc(doc(as('s1'), `${Q1}/votes/other`)));
  await assertFails(getDocs(collection(as('s1'), `${Q1}/votes`)));
  await assertSucceeds(getDocs(collection(as('teacher'), `${Q1}/votes`)));
});

test('die Lehrkraft kann nicht abstimmen und fremde Stimmen nicht ändern oder löschen', async () => {
  const db = as('teacher');
  await assertFails(setDoc(doc(db, `${Q1}/votes/teacher`), vote()));
  await assertFails(updateDoc(doc(db, `${Q1}/votes/other`), { answer: 'yes' }));
});

test('beendete Session nimmt keine Stimmen mehr an', async () => {
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), SESSION), { active: false }));
  await assertFails(setDoc(doc(as('s1'), `${Q1}/votes/s1`), vote()));
});

// ------------------------------------------------------------ Session & Teilnehmende

test('Sessions können nicht aufgelistet oder fremd überschrieben werden', async () => {
  await assertFails(getDocs(collection(as('s1'), 'sessions')));
  await assertSucceeds(getDoc(doc(as('s1'), SESSION)));
  await assertFails(setDoc(doc(as('s1'), SESSION), {
    teacherId: 's1', question: '', currentQuestionId: null, active: true, createdAt: serverTimestamp(),
  }));
});

test('nur die Lehrkraft legt Fragen an', async () => {
  await assertFails(setDoc(doc(as('s1'), Q2), { text: 'Fremd', status: 'prepared', createdAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(as('teacher'), Q2), { text: 'Neu', status: 'prepared', createdAt: serverTimestamp() }));
});

test('Teilnehmende: nur eigene uid, Lehrkraft liest die Liste', async () => {
  await assertSucceeds(setDoc(doc(as('s1'), `${SESSION}/participants/s1`), { joinedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(as('s1'), `${SESSION}/participants/s2`), { joinedAt: serverTimestamp() }));
  await assertFails(getDocs(collection(as('s1'), `${SESSION}/participants`)));
  await assertSucceeds(getDocs(collection(as('teacher'), `${SESSION}/participants`)));
});
