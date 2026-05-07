/**
 * test/my-day.test.js — Tests for My Day API (E1-01, E1-02, E1-06).
 *
 * Contract tests for:
 * - E1-01: My Day API contract (aggregated endpoint)
 * - E1-02: Prioritization service (risk scoring)
 * - E1-06: Event instrumentation baseline (stub)
 */

import assert from 'assert';
import { afterEach, beforeEach, describe, it } from 'node:test';

import WorkspaceTask from '../src/models/WorkspaceTask.js';
import { getMyDay, getMyDayStats } from '../src/services/myDayService.js';

describe('E1: My Day cockpit', function () {
    const testRoomId = 'room-123';
    const userId = 'user-alice';
    const userBobId = 'user-bob';
    let originalFind;
    let mockedTasks = [];

    function taskFixture(overrides = {}) {
        const createdAt = overrides.createdAt || new Date('2026-05-01T09:00:00.000Z');
        return {
            _id: overrides._id || `task-${Math.random().toString(36).slice(2, 10)}`,
            roomId: testRoomId,
            title: overrides.title || 'Task',
            description: overrides.description || '',
            status: overrides.status || 'todo',
            ownerId: overrides.ownerId || userId,
            ownerName: overrides.ownerName || 'Alice',
            dueDate: Object.prototype.hasOwnProperty.call(overrides, 'dueDate')
                ? overrides.dueDate
                : null,
            createdAt,
            updatedAt: overrides.updatedAt || createdAt,
        };
    }

    beforeEach(async function () {
        originalFind = WorkspaceTask.find;
        mockedTasks = [];
        WorkspaceTask.find = (query = {}) => ({
            lean() {
                return this;
            },
            exec() {
                const filtered = mockedTasks.filter((task) => {
                    if (query.roomId && task.roomId !== query.roomId) return false;
                    if (query.status?.$ne && task.status === query.status.$ne) return false;
                    if (query.createdAt?.$exists && !task.createdAt) return false;
                    return true;
                });
                return Promise.resolve(filtered);
            },
        });
    });

    afterEach(async function () {
        WorkspaceTask.find = originalFind;
    });

    describe('E1-01: My Day API contract', function () {
        it('should return empty sections for room with no tasks', async function () {
            mockedTasks = [];

            const result = await getMyDay(testRoomId, userId);

            assert(result.ok === true);
            assert(Array.isArray(result.top3));
            assert(Array.isArray(result.blocked));
            assert(Array.isArray(result.dueToday));
            assert(Array.isArray(result.waitingFor));
            assert.strictEqual(result.top3.length, 0);
            assert.strictEqual(result.blocked.length, 0);
        });

        it('should return typed payloads with required metadata', async function () {
            const now = new Date();
            const tomorrow = new Date(now.getTime() + 86400000);

            mockedTasks = [taskFixture({
                _id: 'task-1',
                title: 'Test task',
                description: 'A long description for testing',
                status: 'todo',
                ownerId: userId,
                ownerName: 'Alice',
                dueDate: tomorrow,
                createdAt: now,
            })];

            const result = await getMyDay(testRoomId, userId);

            assert(result.top3.length > 0, 'should have task in top 3');
            const task = result.top3[0];

            assert(task.id);
            assert.strictEqual(task.kind, 'task');
            assert(task.title);
            assert(task.ownerName);
            assert(task.dueDate);
            assert(task.priority);
            assert(task.whyRanked);
            assert(task.sourceUrl);
            assert(result.requestId);
        });

        it('should return <400ms p50 for baseline data volume', async function () {
            mockedTasks = [];
            for (let i = 0; i < 50; i++) {
                mockedTasks.push(taskFixture({
                    _id: `task-${i}`,
                    title: `Task ${i}`,
                    status: 'todo',
                    ownerId: userId,
                }));
            }

            const start = Date.now();
            await getMyDay(testRoomId, userId);
            const elapsed = Date.now() - start;

            assert(elapsed < 400, `Expected <400ms, got ${elapsed}ms`);
        });
    });

    describe('E1-02: Prioritization service', function () {
        it('should score overdue tasks as highest priority', async function () {
            const yesterday = new Date(Date.now() - 86400000);
            const tomorrow = new Date(Date.now() + 86400000);

            mockedTasks = [
                taskFixture({
                    _id: 'task-overdue',
                    title: 'Overdue task',
                    status: 'todo',
                    ownerId: userId,
                    dueDate: yesterday,
                }),
                taskFixture({
                    _id: 'task-future',
                    title: 'Future task',
                    status: 'todo',
                    ownerId: userId,
                    dueDate: tomorrow,
                }),
            ];

            const result = await getMyDay(testRoomId, userId);

            assert.strictEqual(result.top3.length, 2);
            assert(result.top3[0].whyRanked.includes('Overdue'));
        });

        it('should prioritize blocked tasks', async function () {
            mockedTasks = [
                taskFixture({
                    _id: 'task-blocked',
                    title: 'Blocked task',
                    status: 'blocked',
                    ownerId: userId,
                }),
                taskFixture({
                    _id: 'task-normal',
                    title: 'Normal task',
                    status: 'todo',
                    ownerId: userId,
                }),
            ];

            const result = await getMyDay(testRoomId, userId);

            assert(result.blocked.length > 0, 'should have blocked section');
            assert(result.top3.some((t) => t.title === 'Blocked task'), 'blocked task in top 3');
        });

        it('should separate waiting-for (tasks owned by others)', async function () {
            mockedTasks = [
                taskFixture({
                    _id: 'task-bob',
                    title: 'Bob\'s task',
                    status: 'todo',
                    ownerId: userBobId,
                    ownerName: 'Bob',
                }),
                taskFixture({
                    _id: 'task-alice',
                    title: 'Alice\'s task',
                    status: 'todo',
                    ownerId: userId,
                    ownerName: 'Alice',
                }),
            ];

            const result = await getMyDay(testRoomId, userId);

            assert(result.waitingFor.length > 0, 'should have waiting-for section');
            assert(result.waitingFor.some((t) => t.title === 'Bob\'s task'), 'Bob\'s task in waiting-for');
        });

        it('should populate dueToday section', async function () {
            const now = new Date();
            const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

            mockedTasks = [taskFixture({
                _id: 'task-due-today',
                title: 'Due today',
                status: 'todo',
                ownerId: userId,
                dueDate: todayStart,
                createdAt: now,
            })];

            const result = await getMyDay(testRoomId, userId);

            assert(result.dueToday.length > 0, 'should have dueToday section');
            assert(result.dueToday.some((t) => t.title === 'Due today'), 'task due today in dueToday');
        });

        it('should exclude completed tasks', async function () {
            mockedTasks = [
                taskFixture({
                    _id: 'task-done',
                    title: 'Completed task',
                    status: 'done',
                    ownerId: userId,
                }),
            ];

            const result = await getMyDay(testRoomId, userId);

            assert(!result.top3.some((t) => t.title === 'Completed task'), 'done task should not be in results');
        });
    });

    describe('E1-06: DES instrumentation baseline', function () {
        it('should compute summary stats', async function () {
            const tomorrow = new Date(Date.now() + 86400000);
            mockedTasks = [
                taskFixture({
                    _id: 'task-priority',
                    title: 'Priority 1',
                    status: 'todo',
                    ownerId: userId,
                    dueDate: tomorrow,
                }),
                taskFixture({
                    _id: 'task-blocked',
                    title: 'Blocked',
                    status: 'blocked',
                    ownerId: userId,
                }),
            ];

            const stats = await getMyDayStats(testRoomId, userId);

            assert(stats.totalTop3 >= 0);
            assert(stats.totalBlocked >= 1);
            assert(stats.totalDueToday >= 0);
            assert(stats.urgentCount >= 0);
        });
    });
});
