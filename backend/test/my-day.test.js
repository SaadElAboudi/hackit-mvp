/**
 * test/my-day.test.js — Tests for My Day API (E1-01, E1-02, E1-06).
 *
 * Contract tests for:
 * - E1-01: My Day API contract (aggregated endpoint)
 * - E1-02: Prioritization service (risk scoring)
 * - E1-06: Event instrumentation baseline (stub)
 */

import assert from 'assert';
import mongoose from 'mongoose';
import Room from '../src/models/Room.js';
import WorkspaceTask from '../src/models/WorkspaceTask.js';
import { getMyDay, getMyDayStats } from '../src/services/myDayService.js';

describe('E1: My Day cockpit', function () {
    let testRoom;
    let userId = 'user-alice';
    let userBobId = 'user-bob';

    beforeEach(async function () {
        // Create test room
        testRoom = await Room.create({
            name: 'Test Room',
            type: 'channel',
            ownerId: userId,
            members: [
                { userId, displayName: 'Alice', role: 'owner' },
                { userId: userBobId, displayName: 'Bob', role: 'member' },
            ],
        });
    });

    afterEach(async function () {
        // Cleanup
        await WorkspaceTask.deleteMany({ roomId: testRoom._id });
        await Room.deleteOne({ _id: testRoom._id });
    });

    describe('E1-01: My Day API contract', function () {
        it('should return empty sections for room with no tasks', async function () {
            const result = await getMyDay(testRoom._id, userId);

            assert(result.ok === true);
            assert(Array.isArray(result.top3));
            assert(Array.isArray(result.blocked));
            assert(Array.isArray(result.dueToday));
            assert(Array.isArray(result.waitingFor));
            assert.strictEqual(result.top3.length, 0);
            assert.strictEqual(result.blocked.length, 0);
        });

        it('should return typed payloads with required metadata', async function () {
            // Create a task
            const now = new Date();
            const tomorrow = new Date(now.getTime() + 86400000);

            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Test task',
                description: 'A long description for testing',
                status: 'todo',
                ownerId: userId,
                ownerName: 'Alice',
                dueDate: tomorrow,
                createdBy: userId,
                createdByName: 'Alice',
            });

            const result = await getMyDay(testRoom._id, userId);

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
            // Create 50 tasks
            const tasks = [];
            for (let i = 0; i < 50; i++) {
                tasks.push({
                    roomId: testRoom._id,
                    title: `Task ${i}`,
                    status: 'todo',
                    ownerId: userId,
                    createdBy: userId,
                });
            }
            await WorkspaceTask.insertMany(tasks);

            const start = Date.now();
            await getMyDay(testRoom._id, userId);
            const elapsed = Date.now() - start;

            assert(elapsed < 400, `Expected <400ms, got ${elapsed}ms`);
        });
    });

    describe('E1-02: Prioritization service', function () {
        it('should score overdue tasks as highest priority', async function () {
            const yesterday = new Date(Date.now() - 86400000);
            const tomorrow = new Date(Date.now() + 86400000);

            // Create overdue task
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Overdue task',
                status: 'todo',
                ownerId: userId,
                dueDate: yesterday,
                createdBy: userId,
            });

            // Create due tomorrow task
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Future task',
                status: 'todo',
                ownerId: userId,
                dueDate: tomorrow,
                createdBy: userId,
            });

            const result = await getMyDay(testRoom._id, userId);

            assert.strictEqual(result.top3.length, 2);
            assert(result.top3[0].whyRanked.includes('Overdue'));
        });

        it('should prioritize blocked tasks', async function () {
            // Create blocked task
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Blocked task',
                status: 'blocked',
                ownerId: userId,
                createdBy: userId,
            });

            // Create normal task
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Normal task',
                status: 'todo',
                ownerId: userId,
                createdBy: userId,
            });

            const result = await getMyDay(testRoom._id, userId);

            assert(result.blocked.length > 0, 'should have blocked section');
            assert(result.top3.some((t) => t.title === 'Blocked task'), 'blocked task in top 3');
        });

        it('should separate waiting-for (tasks owned by others)', async function () {
            // Create task owned by Bob
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Bob\'s task',
                status: 'todo',
                ownerId: userBobId,
                ownerName: 'Bob',
                createdBy: userId,
            });

            // Create task owned by Alice
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Alice\'s task',
                status: 'todo',
                ownerId: userId,
                ownerName: 'Alice',
                createdBy: userId,
            });

            const result = await getMyDay(testRoom._id, userId);

            assert(result.waitingFor.length > 0, 'should have waiting-for section');
            assert(result.waitingFor.some((t) => t.title === 'Bob\'s task'), 'Bob\'s task in waiting-for');
        });

        it('should populate dueToday section', async function () {
            const now = new Date();
            const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
            const todayEnd = new Date(todayStart.getTime() + 86400000);

            // Create task due today
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Due today',
                status: 'todo',
                ownerId: userId,
                dueDate: todayStart,
                createdBy: userId,
            });

            const result = await getMyDay(testRoom._id, userId);

            assert(result.dueToday.length > 0, 'should have dueToday section');
            assert(result.dueToday.some((t) => t.title === 'Due today'), 'task due today in dueToday');
        });

        it('should exclude completed tasks', async function () {
            // Create done task
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Completed task',
                status: 'done',
                ownerId: userId,
                createdBy: userId,
            });

            const result = await getMyDay(testRoom._id, userId);

            assert(!result.top3.some((t) => t.title === 'Completed task'), 'done task should not be in results');
        });
    });

    describe('E1-06: DES instrumentation baseline', function () {
        it('should compute summary stats', async function () {
            // Create mix of tasks
            const tomorrow = new Date(Date.now() + 86400000);
            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Priority 1',
                status: 'todo',
                ownerId: userId,
                dueDate: tomorrow,
                createdBy: userId,
            });

            await WorkspaceTask.create({
                roomId: testRoom._id,
                title: 'Blocked',
                status: 'blocked',
                ownerId: userId,
                createdBy: userId,
            });

            const stats = await getMyDayStats(testRoom._id, userId);

            assert(stats.totalTop3 >= 0);
            assert(stats.totalBlocked >= 1);
            assert(stats.totalDueToday >= 0);
            assert(stats.urgentCount >= 0);
        });
    });
});
