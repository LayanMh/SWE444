import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

const errorRate = new Rate('errors');

export const options = {
  vus: 15,
  duration: '32s',
  thresholds: {
    http_req_duration: ['p(95)<310'],
    errors: ['rate<0.05'],
  },
};

// Fixed: Added quotes around project ID
const FIREBASE_PROJECT_ID = 'absherk-e89ba';
const FIRESTORE_API = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents`;

export default function () {
  const action = Math.random();
  
  if (action < 0.625) {
    testFriendRequest();
  } else {
    testOuting();
  }
  
  sleep(Math.random() * 1.5 + 0.5);
}

function testFriendRequest() {
  const res = http.get(`${FIRESTORE_API}/swap_requests`, {
    headers: {
      'Content-Type': 'application/json',
    },
  });
  
  const success = check(res, {
    'friend request status ok': (r) => r.status === 200,
    'response time acceptable': (r) => r.timings.duration < 500,
  });
  
  errorRate.add(!success);
}

function testOuting() {
  const res = http.get(`${FIRESTORE_API}/users`, {
    headers: {
      'Content-Type': 'application/json',
    },
  });
  
  const success = check(res, {
    'outing status ok': (r) => r.status === 200,
    'response time acceptable': (r) => r.timings.duration < 500,
  });
  
  errorRate.add(!success);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
  };
}