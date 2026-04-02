import mongoose from 'mongoose';
import User from '../src/models/User.js';

mongoose.connect('mongodb://localhost:27017/hackit', { useNewUrlParser: true, useUnifiedTopology: true })
    .then(async () => {
        const users = await User.find({}, 'email');
        console.log('Utilisateurs:');
        users.forEach(u => console.log(u.email));
        mongoose.disconnect();
    })
    .catch(err => {
        console.error('Erreur de connexion MongoDB:', err);
    });
