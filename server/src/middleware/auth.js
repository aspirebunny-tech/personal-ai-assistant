const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Token nahi mila — pehle login karo' });
  }

  try {
    const user = jwt.verify(token, process.env.JWT_SECRET || 'default_secret');
    req.user = user;
    next();
  } catch (err) {
    return res.status(403).json({ error: 'Token invalid hai — dobara login karo' });
  }
}

module.exports = authMiddleware;
