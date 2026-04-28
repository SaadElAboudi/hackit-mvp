import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';

import {
    broadcastPageBlockUpdated,
    broadcastRoomMessage,
    handleRoomConnection,
} from '../src/services/roomWS.js';

class FakeSocket extends EventEmitter {
    constructor() {
        super();
        this.readyState = 1;
        this.frames = [];
    }

    send(raw) {
        this.frames.push(JSON.parse(String(raw)));
    }

    close() {
        this.readyState = 3;
        this.emit('close');
    }
}

await test('WS guard drops non-serializable broadcast payload without crashing', async () => {
    const roomId = '507f191e810c19729de860ea';
    const ws = new FakeSocket();
    handleRoomConnection(ws, { url: `/ws/rooms/${roomId}` });

    ws.emit(
        'message',
        Buffer.from(
            JSON.stringify({
                type: 'join',
                roomId,
                userId: 'ws-guard-user',
                displayName: 'Guard User',
            })
        )
    );

    const circular = { value: 1 };
    circular.self = circular;

    assert.doesNotThrow(() => {
        broadcastPageBlockUpdated(roomId, {
            action: 'created',
            pageId: 'p1',
            block: circular,
        });
    });

    const hasPageBlockEvent = ws.frames.some((f) => f.type === 'page.block.updated');
    assert.equal(hasPageBlockEvent, false);

    ws.close();
});

await test('WS guard keeps valid broadcast payloads working', async () => {
    const roomId = '507f191e810c19729de860eb';
    const ws = new FakeSocket();
    handleRoomConnection(ws, { url: `/ws/rooms/${roomId}` });

    ws.emit(
        'message',
        Buffer.from(
            JSON.stringify({
                type: 'join',
                roomId,
                userId: 'ws-guard-user-2',
                displayName: 'Guard User 2',
            })
        )
    );

    broadcastRoomMessage(roomId, {
        _id: 'm1',
        roomId,
        senderId: 'u1',
        senderName: 'U1',
        isAI: false,
        content: 'hello',
    });

    const msg = ws.frames.find((f) => f.type === 'message');
    assert.ok(msg);
    assert.equal(msg.roomId, roomId);

    ws.close();
});
