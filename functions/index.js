/**
 * Hangout Push Notification Cloud Functions
 *
 * Deploy:
 *   1. Install Firebase CLI: npm install -g firebase-tools
 *   2. cd functions && npm install
 *   3. cd .. && firebase deploy --only functions
 *
 * These functions run on the Firebase Blaze plan free tier
 * (2M invocations/month included at no cost).
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// ─────────────────────────────────────────────────────────────────────────
// 1. Send push when a new call is created
// ─────────────────────────────────────────────────────────────────────────
exports.onNewCall = functions.firestore
  .document("calls/{callId}")
  .onCreate(async (snap, context) => {
    const call = snap.data();
    if (!call) return;

    const calleeId = call.calleeId;

    // Fetch the callee's FCM token from Firestore.
    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(calleeId)
      .get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) {
      console.log(`No FCM token for user ${calleeId}`);
      return;
    }

    const message = {
      token: fcmToken,
      data: {
        type: "incoming_call",
        callId: context.params.callId,
        channelName: call.channelName || "",
        callerId: call.callerId || "",
        callerName: call.callerName || "Someone",
        isVideo: call.type === "video" ? "true" : "false",
      },
      android: { priority: "high" },
      apns: {
        payload: {
          aps: {
            alert: {
              title: `Incoming ${call.type || "audio"} call`,
              body: `${call.callerName || "Someone"} is calling...`,
            },
            sound: "default",
            "content-available": 1,
          },
        },
        headers: {
          "apns-push-type": "background",
          "apns-priority": "5",
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log(`Push sent for call ${context.params.callId}`);
    } catch (err) {
      console.error("Failed to send call push:", err);
    }
  });

// ─────────────────────────────────────────────────────────────────────────
// 2. Send push when a new chat message is created
// ─────────────────────────────────────────────────────────────────────────
exports.onNewMessage = functions.firestore
  .document("chats/{chatId}/messages/{msgId}")
  .onCreate(async (snap, context) => {
    const msg = snap.data();
    if (!msg) return;

    const chatId = context.params.chatId;

    // Find the recipient (the participant who is NOT the sender).
    const chatDoc = await admin
      .firestore()
      .collection("chats")
      .doc(chatId)
      .get();
    if (!chatDoc.exists) return;

    const participants = chatDoc.data()?.participants || [];
    const receiverId = participants.find((id) => id !== msg.authorId);
    if (!receiverId) return;

    // Get the recipient's FCM token.
    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(receiverId)
      .get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) return;

    const message = {
      token: fcmToken,
      data: {
        type: "message",
        chatId: chatId,
        senderId: msg.authorId || "",
        senderName: msg.authorName || "Someone",
        text: msg.text || "",
      },
      android: { priority: "high" },
      apns: {
        payload: {
          aps: {
            alert: {
              title: msg.authorName || "Message",
              body: msg.text || "",
            },
            sound: "default",
          },
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log(`Push sent for message ${context.params.msgId}`);
    } catch (err) {
      console.error("Failed to send message push:", err);
    }
  });
