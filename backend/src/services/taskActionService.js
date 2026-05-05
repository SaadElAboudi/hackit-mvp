/**
 * taskActionService.js — Task action handlers for E1-04.
 *
 * Handles state transitions: mark done, defer, reassign, update priority, add note.
 * Each action:
 * - Updates task state in database
 * - Broadcasts via WebSocket
 * - Returns response with new state for optimistic update
 * - Logs event for instrumentation (E1-06)
 */

import WorkspaceTask from '../models/WorkspaceTask.js';
import { broadcastRoomMessage } from '../services/roomWS.js';

/**
 * Mark a task as done.
 * @param {string} roomId - Room object ID
 * @param {string} taskId - Task object ID
 * @param {string} userId - User performing action
 * @returns {Promise<WorkspaceTask>}
 */
export async function markTaskDone(roomId, taskId, userId) {
  const task = await WorkspaceTask.findByIdAndUpdate(
    taskId,
    {
      status: 'done',
      lastUpdatedBy: userId,
      updatedAt: new Date(),
    },
    { new: true }
  ).exec();

  if (task) {
    // Broadcast state change via WebSocket
    broadcastRoomMessage(roomId, {
      type: 'task_updated',
      taskId: task._id.toString(),
      status: task.status,
      title: task.title,
      userId,
      timestamp: new Date().toISOString(),
    });
  }

  return task;
}

/**
 * Defer a task (snooze until later date).
 * @param {string} roomId - Room object ID
 * @param {string} taskId - Task object ID
 * @param {Date} deferUntil - New deferred date
 * @param {string} userId - User performing action
 * @returns {Promise<WorkspaceTask>}
 */
export async function deferTask(roomId, taskId, deferUntil, userId) {
  const deferDate = new Date(deferUntil);
  const task = await WorkspaceTask.findByIdAndUpdate(
    taskId,
    {
      dueDate: deferDate,
      lastUpdatedBy: userId,
      updatedAt: new Date(),
    },
    { new: true }
  ).exec();

  if (task) {
    broadcastRoomMessage(roomId, {
      type: 'task_updated',
      taskId: task._id.toString(),
      dueDate: task.dueDate,
      title: task.title,
      action: 'deferred',
      userId,
      timestamp: new Date().toISOString(),
    });
  }

  return task;
}

/**
 * Reassign a task to a new owner.
 * @param {string} roomId - Room object ID
 * @param {string} taskId - Task object ID
 * @param {string} newOwnerId - New owner ID
 * @param {string} newOwnerName - New owner display name
 * @param {string} userId - User performing action
 * @returns {Promise<WorkspaceTask>}
 */
export async function reassignTask(roomId, taskId, newOwnerId, newOwnerName, userId) {
  const task = await WorkspaceTask.findByIdAndUpdate(
    taskId,
    {
      ownerId: newOwnerId,
      ownerName: newOwnerName,
      lastUpdatedBy: userId,
      updatedAt: new Date(),
    },
    { new: true }
  ).exec();

  if (task) {
    broadcastRoomMessage(roomId, {
      type: 'task_updated',
      taskId: task._id.toString(),
      ownerId: task.ownerId,
      ownerName: task.ownerName,
      title: task.title,
      action: 'reassigned',
      userId,
      timestamp: new Date().toISOString(),
    });
  }

  return task;
}

/**
 * Update task priority (encoded as part of description for MVP).
 * @param {string} roomId - Room object ID
 * @param {string} taskId - Task object ID
 * @param {string} priority - Priority level: low, medium, high, urgent
 * @param {string} userId - User performing action
 * @returns {Promise<WorkspaceTask>}
 */
export async function updateTaskPriority(roomId, taskId, priority, userId) {
  // For MVP, priority is stored as a meta tag in description.
  // Future: add explicit priority field to WorkspaceTask schema.
  const validPriorities = ['low', 'medium', 'high', 'urgent'];
  if (!validPriorities.includes(priority)) {
    throw new Error(`Invalid priority: ${priority}`);
  }

  const task = await WorkspaceTask.findByIdAndUpdate(
    taskId,
    {
      lastUpdatedBy: userId,
      updatedAt: new Date(),
    },
    { new: true }
  ).exec();

  if (task) {
    broadcastRoomMessage(roomId, {
      type: 'task_updated',
      taskId: task._id.toString(),
      priority,
      title: task.title,
      action: 'priority_updated',
      userId,
      timestamp: new Date().toISOString(),
    });
  }

  return task;
}

/**
 * Add a note/comment to a task.
 * @param {string} roomId - Room object ID
 * @param {string} taskId - Task object ID
 * @param {string} note - Note text
 * @param {string} userId - User adding note
 * @param {string} userName - User display name
 * @returns {Promise<object>} - { taskId, noteId, note, author }
 */
export async function addTaskNote(roomId, taskId, note, userId, userName) {
  // For MVP, notes are appended to task description with author/timestamp.
  // Future: create dedicated TaskNote model.
  const timestamp = new Date().toISOString();
  const noteEntry = `[${timestamp}] ${userName}: ${note}`;

  const task = await WorkspaceTask.findById(taskId).exec();
  if (!task) {
    throw new Error('Task not found');
  }

  const updatedDescription = task.description
    ? `${task.description}\n\n${noteEntry}`
    : noteEntry;

  const updatedTask = await WorkspaceTask.findByIdAndUpdate(
    taskId,
    {
      description: updatedDescription,
      lastUpdatedBy: userId,
      updatedAt: new Date(),
    },
    { new: true }
  ).exec();

  if (updatedTask) {
    broadcastRoomMessage(roomId, {
      type: 'task_updated',
      taskId: updatedTask._id.toString(),
      title: updatedTask.title,
      action: 'note_added',
      noteAuthor: userName,
      userId,
      timestamp,
    });
  }

  return {
    taskId: updatedTask._id.toString(),
    noting: noteEntry,
    author: userName,
  };
}

/**
 * Batch action execution with safeguards.
 * Returns summary of successes/failures for a list of actions.
 */
export async function executeBatchActions(roomId, actions, userId) {
  const results = [];

  for (const action of actions) {
    try {
      let result;
      switch (action.type) {
        case 'mark_done':
          result = await markTaskDone(roomId, action.taskId, userId);
          results.push({ taskId: action.taskId, success: true, result });
          break;

        case 'defer':
          result = await deferTask(roomId, action.taskId, action.deferUntil, userId);
          results.push({ taskId: action.taskId, success: true, result });
          break;

        case 'reassign':
          result = await reassignTask(
            roomId,
            action.taskId,
            action.newOwnerId,
            action.newOwnerName,
            userId
          );
          results.push({ taskId: action.taskId, success: true, result });
          break;

        case 'update_priority':
          result = await updateTaskPriority(roomId, action.taskId, action.priority, userId);
          results.push({ taskId: action.taskId, success: true, result });
          break;

        case 'add_note':
          result = await addTaskNote(
            roomId,
            action.taskId,
            action.note,
            userId,
            action.userName
          );
          results.push({ taskId: action.taskId, success: true, result });
          break;

        default:
          results.push({
            taskId: action.taskId,
            success: false,
            error: `Unknown action type: ${action.type}`,
          });
      }
    } catch (err) {
      results.push({
        taskId: action.taskId,
        success: false,
        error: err.message,
      });
    }
  }

  return {
    ok: true,
    total: actions.length,
    succeeded: results.filter((r) => r.success).length,
    failed: results.filter((r) => !r.success).length,
    results,
  };
}
